import AppKit
import Combine
import Darwin
import Foundation

@MainActor
final class FileBrowserController: ObservableObject {
    @Published private(set) var currentURL: URL
    @Published private(set) var items: [LocalFileItem] = []
    @Published private(set) var searchResults: [LocalFileItem] = []
    @Published var selection: Set<URL> = []
    @Published var sort: FileSort {
        didSet {
            guard sort != oldValue else { return }
            persistSort()
            applySort()
        }
    }
    @Published var showsHiddenFiles: Bool {
        didSet {
            guard showsHiddenFiles != oldValue else { return }
            defaults.set(showsHiddenFiles, forKey: Keys.showsHiddenFiles)
            Task { await refresh() }
        }
    }
    @Published var viewMode: FileBrowserViewMode {
        didSet {
            guard viewMode != oldValue else { return }
            defaults.set(viewMode.rawValue, forKey: Keys.viewMode)
        }
    }
    @Published var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            scheduleSearch()
        }
    }
    @Published private(set) var isLoading = false
    @Published private(set) var isSearching = false
    @Published private(set) var isOperating = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var operationFailures: [FileOperationFailure] = []
    @Published private(set) var favorites: [FileBrowserLocation]
    @Published private(set) var lastTrashOperation: TrashOperation?
    @Published private(set) var pasteRequest: FilePasteRequest?

    var displayedItems: [LocalFileItem] {
        normalizedSearchText.isEmpty ? items : searchResults
    }

    var locations: [FileBrowserLocation] {
        builtInLocations + favorites + volumeLocations
    }

    var selectedItems: [LocalFileItem] {
        let selected = selection
        return displayedItems.filter { selected.contains($0.url) }
    }

    var canGoBack: Bool { !backHistory.isEmpty }
    var canGoForward: Bool { !forwardHistory.isEmpty }
    var canGoUp: Bool {
        let parent = currentURL.deletingLastPathComponent().standardizedFileURL
        return parent != currentURL && isAllowed(parent)
    }
    var canPaste: Bool { clipboard != nil || !pasteboardFileURLs().isEmpty }

    private let service: LocalFileService
    private let defaults: UserDefaults
    private let homeURL: URL
    private let builtInLocations: [FileBrowserLocation]
    private var backHistory: [URL] = []
    private var forwardHistory: [URL] = []
    private var sessionAllowedRoots: Set<URL> = []
    private var clipboard: FileClipboard?
    private var hasLoaded = false
    private var loadGeneration = 0
    private var searchGeneration = 0
    private var searchTask: Task<Void, Never>?
    private var metadataQuery: NSMetadataQuery?
    private var metadataQueryObserver: NSObjectProtocol?
    private var refreshDebounceTask: Task<Void, Never>?
    private var trashUndoTask: Task<Void, Never>?
    private var directorySource: DispatchSourceFileSystemObject?
    private var directoryFileDescriptor: Int32 = -1

    init(
        service: LocalFileService = LocalFileService(),
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.service = service
        self.defaults = defaults
        let homeURL = fileManager.homeDirectoryForCurrentUser.standardizedFileURL
        self.homeURL = homeURL

        let builtIns = Self.makeBuiltInLocations(homeURL: homeURL, fileManager: fileManager)
        builtInLocations = builtIns
        let loadedFavorites = Self.loadFavorites(defaults: defaults)
        favorites = loadedFavorites
        sort = Self.loadSort(defaults: defaults)
        showsHiddenFiles = defaults.object(forKey: Keys.showsHiddenFiles) as? Bool ?? false
        viewMode = defaults.string(forKey: Keys.viewMode)
            .flatMap(FileBrowserViewMode.init(rawValue:)) ?? .list

        let savedPath = defaults.string(forKey: Keys.lastPath).map {
            URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
        }
        let allowedRoots = builtIns.map(\.url) + loadedFavorites.map(\.url)
        if let savedPath,
           fileManager.fileExists(atPath: savedPath.path),
           Self.isURL(savedPath, withinAny: allowedRoots) {
            currentURL = savedPath
        } else {
            currentURL = homeURL
        }
    }

    deinit {
        MainActor.assumeIsolated {
            searchTask?.cancel()
            refreshDebounceTask?.cancel()
            trashUndoTask?.cancel()
            metadataQuery?.stop()
            if let metadataQueryObserver {
                NotificationCenter.default.removeObserver(metadataQueryObserver)
            }
            directorySource?.cancel()
        }
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await loadDirectory(currentURL, historyAction: .none)
    }

    func refresh() async {
        await loadDirectory(currentURL, historyAction: .none)
    }

    func navigate(to url: URL) async {
        await loadDirectory(url, historyAction: .pushCurrent)
    }

    func navigate(to location: FileBrowserLocation) async {
        await navigate(to: location.url)
    }

    func goBack() async {
        guard let destination = backHistory.popLast() else { return }
        let previous = currentURL
        await loadDirectory(destination, historyAction: .none)
        if currentURL == destination.standardizedFileURL {
            forwardHistory.append(previous)
        } else {
            backHistory.append(destination)
        }
    }

    func goForward() async {
        guard let destination = forwardHistory.popLast() else { return }
        let previous = currentURL
        await loadDirectory(destination, historyAction: .none)
        if currentURL == destination.standardizedFileURL {
            backHistory.append(previous)
        } else {
            forwardHistory.append(destination)
        }
    }

    func goUp() async {
        guard canGoUp else { return }
        await navigate(to: currentURL.deletingLastPathComponent())
    }

    func open(_ item: LocalFileItem) {
        if item.isBrowsableDirectory {
            Task { await navigate(to: item.url) }
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    func open(_ url: URL) {
        if let item = try? itemFromDisplayedItems(url), item.isBrowsableDirectory {
            Task { await navigate(to: item.url) }
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func openSelection() {
        guard let item = selectedItems.first else { return }
        open(item)
    }

    func revealInFinder(_ item: LocalFileItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func createFolder(named name: String) async {
        await performOperation {
            let item = try await self.service.createFolder(named: name, in: self.currentURL)
            await self.refresh()
            self.selection = [item.url]
        }
    }

    func createFile(named name: String) async {
        await performOperation {
            let item = try await self.service.createFile(named: name, in: self.currentURL)
            await self.refresh()
            self.selection = [item.url]
        }
    }

    func rename(_ item: LocalFileItem, to name: String) async {
        guard !isProtectedRoot(item.url) else {
            errorMessage = "This location cannot be renamed."
            return
        }
        await performOperation {
            let renamed = try await self.service.rename(item.url, to: name)
            await self.refresh()
            self.selection = [renamed.url]
        }
    }

    func copySelection() {
        setClipboard(urls: selectedItems.map(\.url), operation: .copy)
    }

    func copySelectionToClipboard() {
        copySelection()
    }

    func cutSelection() {
        let movable = selectedItems.map(\.url).filter { !isProtectedRoot($0) }
        setClipboard(urls: movable, operation: .move)
    }

    func hasPasteConflicts() async -> Bool {
        let urls = clipboard?.urls ?? pasteboardFileURLs()
        guard !urls.isEmpty else { return false }
        return (try? await service.hasConflicts(urls, in: currentURL)) ?? false
    }

    func hasConflicts(_ urls: [URL], in destination: URL) async -> Bool {
        guard !urls.isEmpty, isAllowed(destination) else { return false }
        return (try? await service.hasConflicts(urls, in: destination)) ?? false
    }

    func requestPaste(moving: Bool) {
        pasteRequest = FilePasteRequest(moving: moving)
    }

    func consumePasteRequest() {
        pasteRequest = nil
    }

    func paste(
        moving: Bool = false,
        conflictResolution: FileConflictResolution = .keepBoth
    ) async {
        let board = clipboard
        let urls = board?.urls ?? pasteboardFileURLs()
        guard !urls.isEmpty else { return }
        let shouldMove = moving || board?.operation == .move
        await transfer(
            urls,
            to: currentURL,
            moving: shouldMove,
            conflictResolution: conflictResolution
        )
        if shouldMove, errorMessage == nil {
            clipboard = nil
        }
    }

    func receiveDrop(
        _ urls: [URL],
        to destination: URL? = nil,
        moving: Bool = true,
        conflictResolution: FileConflictResolution = .keepBoth
    ) async {
        let destination = destination ?? currentURL
        guard isAllowed(destination) else {
            errorMessage = "Choose a folder from your locations before moving files there."
            return
        }
        await transfer(
            urls,
            to: destination,
            moving: moving,
            conflictResolution: conflictResolution
        )
    }

    func trashSelection() async {
        await trash(selectedItems)
    }

    func trash(_ item: LocalFileItem) async {
        await trash([item])
    }

    func undoLastTrash(
        conflictResolution: FileConflictResolution = .keepBoth
    ) async {
        guard let operation = lastTrashOperation else { return }
        trashUndoTask?.cancel()
        await performOperation {
            let result = await self.service.restore(
                operation,
                conflictResolution: conflictResolution
            )
            await self.refresh()
            self.consume(result)
            let failedSources = Set(result.failures.map(\.sourceURL))
            let skippedSources = Set(result.skippedURLs)
            let remaining = operation.files.filter {
                failedSources.contains($0.trashedURL) || skippedSources.contains($0.trashedURL)
            }
            self.lastTrashOperation = remaining.isEmpty
                ? nil
                : TrashOperation(files: remaining, createdAt: operation.createdAt)
        }
    }

    func addFavorite(_ url: URL) {
        let url = url.standardizedFileURL
        guard !favorites.contains(where: { $0.url == url }),
              !builtInLocations.contains(where: { $0.url == url })
        else { return }

        favorites.append(
            FileBrowserLocation(name: url.lastPathComponent, url: url, kind: .favorite)
        )
        persistFavorites()
    }

    func allowAccessForSession(to url: URL) {
        sessionAllowedRoots.insert(url.standardizedFileURL)
    }

    func removeFavorite(_ location: FileBrowserLocation) {
        guard location.kind == .favorite else { return }
        favorites.removeAll { $0.id == location.id }
        persistFavorites()
        if !isAllowed(currentURL) {
            Task { await navigate(to: homeURL) }
        }
    }

    func toggleHiddenFiles() {
        showsHiddenFiles.toggle()
    }

    func clearError() {
        errorMessage = nil
        operationFailures = []
    }

    private func loadDirectory(_ requestedURL: URL, historyAction: HistoryAction) async {
        let url = requestedURL.standardizedFileURL
        guard isAllowed(url) else {
            errorMessage = "This folder is outside your file locations. Add it as a favorite first."
            return
        }

        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        do {
            let loadedItems = try await service.contents(
                of: url,
                includingHidden: showsHiddenFiles
            )
            guard generation == loadGeneration else { return }

            let previous = currentURL
            currentURL = url
            items = sorted(loadedItems)
            selection.removeAll()
            errorMessage = nil
            defaults.set(url.path, forKey: Keys.lastPath)
            if previous != url {
                switch historyAction {
                case .none:
                    break
                case .pushCurrent:
                    backHistory.append(previous)
                    forwardHistory.removeAll()
                }
            }
            restartDirectoryWatcher(for: url)
            scheduleSearch(immediate: true)
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
        }
        if generation == loadGeneration {
            isLoading = false
        }
    }

    private func transfer(
        _ urls: [URL],
        to destination: URL,
        moving: Bool,
        conflictResolution: FileConflictResolution
    ) async {
        let protectedSources = moving ? urls.filter(isProtectedRoot) : []
        guard protectedSources.isEmpty else {
            errorMessage = "A file location itself cannot be moved."
            return
        }

        await performOperation {
            let result: FileOperationResult
            if moving {
                result = try await self.service.move(
                    urls,
                    to: destination,
                    conflictResolution: conflictResolution
                )
            } else {
                result = try await self.service.copy(
                    urls,
                    to: destination,
                    conflictResolution: conflictResolution
                )
            }
            await self.refresh()
            self.consume(result)
            self.selection = Set(result.completedURLs)
        }
    }

    private func trash(_ selectedItems: [LocalFileItem]) async {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        guard !urls.contains(where: isProtectedRoot) else {
            errorMessage = "A file location itself cannot be moved to the Trash."
            return
        }

        await performOperation {
            let (result, operation) = await self.service.trash(urls)
            if let operation {
                self.lastTrashOperation = operation
                self.scheduleTrashUndoExpiration(for: operation.id)
            }
            await self.refresh()
            self.consume(result)
        }
    }

    private func performOperation(_ operation: () async throws -> Void) async {
        guard !isOperating else { return }
        isOperating = true
        errorMessage = nil
        operationFailures = []
        defer { isOperating = false }
        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func consume(_ result: FileOperationResult) {
        operationFailures = result.failures
        guard !result.failures.isEmpty else {
            errorMessage = nil
            return
        }
        let first = result.failures[0].message
        errorMessage = result.failures.count == 1
            ? first
            : "\(result.failures.count) items failed. \(first)"
    }

    private func scheduleSearch(immediate: Bool = false) {
        searchTask?.cancel()
        stopSpotlightSearch()
        searchGeneration += 1
        let generation = searchGeneration
        let query = normalizedSearchText
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        let directory = currentURL
        isSearching = true
        searchTask = Task { [weak self] in
            do {
                if !immediate {
                    try await Task.sleep(for: .milliseconds(250))
                }
                try Task.checkCancellation()
                guard let self, generation == self.searchGeneration else { return }
                self.beginSpotlightSearch(
                    query: query,
                    directory: directory,
                    generation: generation
                )
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func beginSpotlightSearch(
        query searchTerm: String,
        directory: URL,
        generation: Int
    ) {
        stopSpotlightSearch()

        let query = NSMetadataQuery()
        query.searchScopes = [directory]
        query.predicate = NSPredicate(
            format: "%K CONTAINS[cd] %@",
            NSMetadataItemFSNameKey,
            searchTerm
        )
        query.sortDescriptors = [
            NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: true),
        ]

        metadataQuery = query
        metadataQueryObserver = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let query = self.metadataQuery else { return }
                self.finishSpotlightSearch(
                    query,
                    searchTerm: searchTerm,
                    directory: directory,
                    generation: generation
                )
            }
        }

        if !query.start() {
            stopSpotlightSearch()
            runFallbackSearch(
                query: searchTerm,
                directory: directory,
                generation: generation
            )
        }
    }

    private func finishSpotlightSearch(
        _ query: NSMetadataQuery,
        searchTerm: String,
        directory: URL,
        generation: Int
    ) {
        guard query === metadataQuery, generation == searchGeneration else { return }
        query.disableUpdates()
        let urls = (0..<query.resultCount).compactMap { index -> URL? in
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
            else { return nil }
            return URL(fileURLWithPath: path)
        }
        stopSpotlightSearch()

        guard !urls.isEmpty else {
            runFallbackSearch(
                query: searchTerm,
                directory: directory,
                generation: generation
            )
            return
        }

        let includesHidden = showsHiddenFiles
        searchTask = Task { [weak self, service] in
            let matches = await service.searchItems(
                at: urls,
                under: directory,
                includingHidden: includesHidden
            )
            guard !Task.isCancelled,
                  let self,
                  generation == self.searchGeneration
            else { return }
            self.searchResults = self.sorted(matches)
            self.isSearching = false
        }
    }

    private func runFallbackSearch(query: String, directory: URL, generation: Int) {
        let includesHidden = showsHiddenFiles
        searchTask?.cancel()
        searchTask = Task { [weak self, service] in
            do {
                let matches = try await service.search(
                    named: query,
                    under: directory,
                    includingHidden: includesHidden
                )
                try Task.checkCancellation()
                guard let self, generation == self.searchGeneration else { return }
                self.searchResults = self.sorted(matches)
                self.isSearching = false
            } catch is CancellationError {
                return
            } catch {
                guard let self, generation == self.searchGeneration else { return }
                self.searchResults = []
                self.isSearching = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func stopSpotlightSearch() {
        metadataQuery?.stop()
        metadataQuery = nil
        if let metadataQueryObserver {
            NotificationCenter.default.removeObserver(metadataQueryObserver)
            self.metadataQueryObserver = nil
        }
    }

    private func applySort() {
        items = sorted(items)
        searchResults = sorted(searchResults)
    }

    private func sorted(_ source: [LocalFileItem]) -> [LocalFileItem] {
        source.sorted { lhs, rhs in
            if lhs.isBrowsableDirectory != rhs.isBrowsableDirectory {
                return lhs.isBrowsableDirectory
            }

            let comparison: ComparisonResult
            switch sort.key {
            case .name:
                comparison = lhs.name.localizedStandardCompare(rhs.name)
            case .size:
                comparison = compare(lhs.size ?? -1, rhs.size ?? -1)
            case .kind:
                comparison = (lhs.localizedTypeDescription ?? lhs.typeIdentifier ?? "")
                    .localizedStandardCompare(rhs.localizedTypeDescription ?? rhs.typeIdentifier ?? "")
            case .modificationDate:
                comparison = compare(lhs.modificationDate ?? .distantPast, rhs.modificationDate ?? .distantPast)
            }

            if comparison == .orderedSame {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return sort.ascending
                ? comparison == .orderedAscending
                : comparison == .orderedDescending
        }
    }

    private func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }

    private func setClipboard(urls: [URL], operation: FileClipboardOperation) {
        let urls = urls.map(\.standardizedFileURL)
        guard !urls.isEmpty else { return }
        clipboard = FileClipboard(urls: urls, operation: operation)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }

    private func pasteboardFileURLs() -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
    }

    private func itemFromDisplayedItems(_ url: URL) throws -> LocalFileItem {
        guard let item = displayedItems.first(where: { $0.url == url.standardizedFileURL }) else {
            throw LocalFileServiceError.itemNotFound(url)
        }
        return item
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isAllowed(_ url: URL) -> Bool {
        let roots = builtInLocations.map(\.url)
            + favorites.map(\.url)
            + volumeLocations.map(\.url)
            + Array(sessionAllowedRoots)
        return Self.isURL(url.standardizedFileURL, withinAny: roots)
    }

    private func isProtectedRoot(_ url: URL) -> Bool {
        let standardized = url.standardizedFileURL
        return locations.contains { $0.url == standardized }
    }

    private static func isURL(_ url: URL, withinAny roots: [URL]) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return roots.contains { root in
            let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
            return path == rootPath || path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
        }
    }

    private func restartDirectoryWatcher(for url: URL) {
        stopDirectoryWatcher()
        let descriptor = Darwin.open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        directoryFileDescriptor = descriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend, .link, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleExternalRefresh()
            }
        }
        source.setCancelHandler {
            Darwin.close(descriptor)
        }
        directorySource = source
        source.resume()
    }

    private func stopDirectoryWatcher() {
        directorySource?.cancel()
        directorySource = nil
        directoryFileDescriptor = -1
    }

    private func scheduleExternalRefresh() {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(350))
                guard let self else { return }
                await self.refresh()
            } catch {
                return
            }
        }
    }

    private func scheduleTrashUndoExpiration(for operationID: UUID) {
        trashUndoTask?.cancel()
        trashUndoTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(10))
                guard let self, self.lastTrashOperation?.id == operationID else {
                    return
                }
                self.lastTrashOperation = nil
            } catch {
                return
            }
        }
    }

    private func persistFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            defaults.set(data, forKey: Keys.favorites)
        }
    }

    private func persistSort() {
        if let data = try? JSONEncoder().encode(sort) {
            defaults.set(data, forKey: Keys.sort)
        }
    }

    private static func loadFavorites(defaults: UserDefaults) -> [FileBrowserLocation] {
        guard let data = defaults.data(forKey: Keys.favorites),
              let locations = try? JSONDecoder().decode([FileBrowserLocation].self, from: data)
        else { return [] }
        return locations.filter { $0.kind == .favorite }
    }

    private static func loadSort(defaults: UserDefaults) -> FileSort {
        guard let data = defaults.data(forKey: Keys.sort),
              let sort = try? JSONDecoder().decode(FileSort.self, from: data)
        else { return .default }
        return sort
    }

    private static func makeBuiltInLocations(
        homeURL: URL,
        fileManager: FileManager
    ) -> [FileBrowserLocation] {
        var result = [FileBrowserLocation(name: "Home", url: homeURL, kind: .home)]
        let definitions: [(FileManager.SearchPathDirectory, String, FileBrowserLocation.Kind)] = [
            (.desktopDirectory, "Desktop", .desktop),
            (.downloadsDirectory, "Downloads", .downloads),
            (.documentDirectory, "Documents", .documents),
            (.picturesDirectory, "Pictures", .pictures),
        ]
        for (directory, name, kind) in definitions {
            if let url = fileManager.urls(for: directory, in: .userDomainMask).first {
                result.append(FileBrowserLocation(name: name, url: url, kind: kind))
            }
        }
        return result
    }

    private var volumeLocations: [FileBrowserLocation] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeIsBrowsableKey,
            .volumeIsInternalKey,
        ]
        return (FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []).compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.volumeIsBrowsable != false,
                  values?.volumeIsInternal != true,
                  url.standardizedFileURL.path != "/"
            else { return nil }
            return FileBrowserLocation(
                name: values?.volumeName ?? url.lastPathComponent,
                url: url,
                kind: .volume
            )
        }
    }

    private enum HistoryAction {
        case none
        case pushCurrent
    }

    private enum Keys {
        static let favorites = "fileBrowser.favorites"
        static let lastPath = "fileBrowser.lastPath"
        static let sort = "fileBrowser.sort"
        static let showsHiddenFiles = "fileBrowser.showsHiddenFiles"
        static let viewMode = "fileBrowser.viewMode"
    }
}
