import AppKit
import QuickLook
import QuickLookThumbnailing
import SwiftUI

struct FileBrowserWorkspace: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: FileBrowserController

    @State private var quickLookURL: URL?
    @State private var namingFile = false
    @State private var fileName = ""
    @State private var namingFolder = false
    @State private var folderName = ""
    @State private var confirmsTrash = false
    @State private var pendingTransfer: PendingTransfer?
    @State private var showingOperationFailures = false
    @State private var pendingLocationID: String?

    var body: some View {
        VStack(spacing: 0) {
            pathBar
            Divider()

            HStack(spacing: 0) {
                locationsPane
                    .frame(width: 170)
                    .frame(maxHeight: .infinity)

                Divider()

                filePane
                    .frame(minWidth: 420, maxWidth: .infinity)
                    .frame(maxHeight: .infinity)

                Divider()

                detailsPane
                    .frame(width: 240)
                    .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(model.text("file.title"))
        .searchable(
            text: $controller.searchText,
            placement: .toolbar,
            prompt: model.text("file.search")
        )
        .toolbar { toolbarContent }
        .quickLookPreview($quickLookURL)
        .alert(model.text("file.newFile"), isPresented: $namingFile) {
            TextField(model.text("file.file.name"), text: $fileName)
            Button(model.text("common.cancel"), role: .cancel) {
                fileName = ""
            }
            Button(model.text("common.create")) {
                let name = fileName
                fileName = ""
                Task { await controller.createFile(named: name) }
            }
            .disabled(fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert(model.text("file.newFolder"), isPresented: $namingFolder) {
            TextField(model.text("file.folder.name"), text: $folderName)
            Button(model.text("common.cancel"), role: .cancel) {
                folderName = ""
            }
            Button(model.text("common.create")) {
                let name = folderName
                folderName = ""
                Task { await controller.createFolder(named: name) }
            }
            .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert(model.text("file.confirm.trash.title"), isPresented: $confirmsTrash) {
            Button(model.text("common.cancel"), role: .cancel) {}
            Button(model.text("file.trash"), role: .destructive) {
                Task { await controller.trashSelection() }
            }
        } message: {
            Text(
                model.text(
                    controller.selectedItems.count > 1
                        ? "file.confirm.trash.multiple"
                        : "file.confirm.trash.item"
                )
            )
        }
        .alert(
            model.text("file.conflict.title"),
            isPresented: Binding(
                get: { pendingTransfer != nil },
                set: { if !$0 { pendingTransfer = nil } }
            ),
            presenting: pendingTransfer
        ) { transfer in
            Button(model.text("file.conflict.keepBoth")) {
                finishTransfer(transfer, resolution: .keepBoth)
            }
            Button(model.text("file.conflict.replace"), role: .destructive) {
                finishTransfer(transfer, resolution: .replace)
            }
            Button(model.text("file.conflict.skip")) {
                finishTransfer(transfer, resolution: .skip)
            }
            Button(model.text("file.conflict.cancel"), role: .cancel) {
                pendingTransfer = nil
            }
        } message: { _ in
            Text(model.text("file.conflict.body"))
        }
        .sheet(isPresented: $showingOperationFailures) {
            NavigationStack {
                List(controller.operationFailures) { failure in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(failure.sourceURL.lastPathComponent)
                            .fontWeight(.medium)
                        Text(failure.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
                .navigationTitle(model.text("file.error.partial.title"))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(model.text("common.close")) {
                            showingOperationFailures = false
                        }
                    }
                }
            }
            .frame(width: 520, height: 330)
        }
        .onChange(of: controller.pasteRequest) { _, request in
            guard let request else { return }
            controller.consumePasteRequest()
            requestPaste(moving: request.moving)
        }
        .task {
            await controller.loadIfNeeded()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                Task { await controller.goBack() }
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!controller.canGoBack)
            .help(model.text("file.back"))

            Button {
                Task { await controller.goForward() }
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!controller.canGoForward)
            .help(model.text("file.forward"))

            Button {
                Task { await controller.goUp() }
            } label: {
                Image(systemName: "arrow.up")
            }
            .disabled(!controller.canGoUp)
            .help(model.text("file.up"))
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Picker(model.text("file.view"), selection: $controller.viewMode) {
                Label(model.text("file.view.list"), systemImage: "list.bullet")
                    .tag(FileBrowserViewMode.list)
                Label(model.text("file.view.icons"), systemImage: "square.grid.2x2")
                    .tag(FileBrowserViewMode.icons)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .labelStyle(.iconOnly)
            .frame(width: 72)
            .help(model.text("file.view"))

            Button {
                fileName = ""
                namingFile = true
            } label: {
                Image(systemName: "doc.badge.plus")
            }
            .help(model.text("file.newFile"))

            Button {
                folderName = ""
                namingFolder = true
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .help(model.text("file.newFolder"))

            Menu {
                Picker(model.text("file.sort"), selection: sortKeyBinding) {
                    ForEach(FileSort.Key.allCases, id: \.self) { key in
                        Text(sortLabel(key)).tag(key)
                    }
                }
                Divider()
                Button {
                    controller.sort = FileSort(
                        key: controller.sort.key,
                        ascending: !controller.sort.ascending
                    )
                } label: {
                    Label(
                        controller.sort.ascending
                            ? model.text("file.sort.ascending")
                            : model.text("file.sort.descending"),
                        systemImage: controller.sort.ascending
                            ? "arrow.up"
                            : "arrow.down"
                    )
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .help(model.text("file.sort"))

            Button {
                controller.toggleHiddenFiles()
            } label: {
                Image(
                    systemName: controller.showsHiddenFiles
                        ? "eye"
                        : "eye.slash"
                )
            }
            .help(
                model.text(
                    controller.showsHiddenFiles
                        ? "file.hidden.hide"
                        : "file.hidden.show"
                )
            )

            Button {
                Task { await controller.refresh() }
            } label: {
                if controller.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(controller.isLoading)
            .help(model.text("file.refresh"))
        }
    }

    private var pathBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .foregroundStyle(Color.accentColor)

            ForEach(Array(pathComponents.enumerated()), id: \.element) { index, url in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Button {
                    Task { await controller.navigate(to: url) }
                } label: {
                    Text(url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(index == pathComponents.count - 1 ? .primary : .secondary)
            }

            Spacer(minLength: 8)

            if controller.isSearching {
                ProgressView()
                    .controlSize(.small)
                    .help(model.text("file.searching"))
            }

            if controller.isOperating {
                ProgressView()
                    .controlSize(.small)
                    .help(model.text("file.loading"))
            }
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var locationsPane: some View {
        VStack(spacing: 0) {
            List(selection: currentLocationBinding) {
                Section(model.text("file.locations")) {
                    ForEach(controller.locations.filter { $0.kind != .volume }) { location in
                        locationRow(location)
                    }
                }

                let volumes = controller.locations.filter { $0.kind == .volume }
                if !volumes.isEmpty {
                    Section(model.text("file.devices")) {
                        ForEach(volumes) { location in
                            locationRow(location)
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            Button {
                chooseFavorite()
            } label: {
                Image(systemName: "plus")
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .frame(height: 30)
            .help(model.text("file.favorite.add"))
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func locationRow(_ location: FileBrowserLocation) -> some View {
        Label(locationDisplayName(location), systemImage: locationIcon(location.kind))
            .tag(location.id)
            .contextMenu {
                Button(model.text("file.open")) {
                    Task { await controller.navigate(to: location) }
                }
                if location.kind == .favorite {
                    Button(model.text("file.favorite.remove"), role: .destructive) {
                        controller.removeFavorite(location)
                    }
                }
            }
    }

    @ViewBuilder
    private var filePane: some View {
        VStack(spacing: 0) {
            if let error = controller.errorMessage {
                errorBanner(error)
            }

            if controller.isLoading && controller.displayedItems.isEmpty {
                loadingState
            } else if controller.displayedItems.isEmpty {
                emptyState
            } else if controller.viewMode == .icons {
                fileGrid
            } else {
                fileList
            }

            if controller.lastTrashOperation != nil {
                undoBar
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var fileList: some View {
        NativeFileListView(
            items: controller.displayedItems,
            selection: controller.selection,
            currentDirectory: controller.currentURL,
            sort: controller.sort,
            columnTitles: nativeColumnTitles,
            menuTitles: nativeMenuTitles,
            selectionChanged: { controller.selection = $0 },
            open: { controller.open($0) },
            rename: { item, name in
                Task { await controller.rename(item, to: name) }
            },
            sortChanged: { controller.sort = $0 },
            performAction: performNativeAction,
            drop: { urls, destination in
                requestDrop(urls, to: destination)
            },
            trash: requestTrash
        )
    }

    private var fileGrid: some View {
        NativeFileIconView(
            items: controller.displayedItems,
            selection: controller.selection,
            currentDirectory: controller.currentURL,
            menuTitles: nativeMenuTitles,
            selectionChanged: { controller.selection = $0 },
            open: { controller.open($0) },
            rename: { item, name in
                Task { await controller.rename(item, to: name) }
            },
            performAction: performNativeAction,
            drop: { urls, destination in
                requestDrop(urls, to: destination)
            },
            trash: requestTrash
        )
    }

    private var detailsPane: some View {
        Group {
            if controller.selectedItems.count == 1,
               let item = controller.selectedItems.first {
                FileDetailsPane(
                    model: model,
                    item: item,
                    open: { controller.open(item) },
                    quickLook: { quickLookURL = item.url },
                    reveal: {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    }
                )
            } else if controller.selectedItems.count > 1 {
                VStack(spacing: 12) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 5) {
                        Text(controller.selectedItems.count, format: .number)
                            .monospacedDigit()
                        Text(model.text("file.detail.items"))
                    }
                    .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label(model.text("file.empty.selection.title"), systemImage: "doc.text.magnifyingglass")
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(model.text("file.loading"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                controller.searchText.isEmpty
                    ? model.text("file.empty.title")
                    : model.text("file.empty.search.title"),
                systemImage: controller.searchText.isEmpty
                    ? "folder"
                    : "magnifyingglass"
            )
        } description: {
            Text(
                controller.searchText.isEmpty
                    ? model.text("file.empty.body")
                    : model.text("file.empty.search.body")
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(error)
                .lineLimit(2)
            Spacer()
            Button(model.text("file.permission.retry")) {
                controller.clearError()
                Task { await controller.refresh() }
            }
            .buttonStyle(.borderless)
            Button(model.text("file.chooseFolder")) {
                chooseFavorite()
            }
            .buttonStyle(.borderless)
            if !controller.operationFailures.isEmpty {
                Button(model.text("file.error.partial.title")) {
                    showingOperationFailures = true
                }
                .buttonStyle(.borderless)
            }
            Button {
                controller.clearError()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }

    private var undoBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash")
            Text(model.text("file.trash.done"))
            Spacer()
            Button(model.text("file.undo")) {
                Task { await controller.undoLastTrash() }
            }
            .buttonStyle(.borderless)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(.regularMaterial)
    }

    private var sortKeyBinding: Binding<FileSort.Key> {
        Binding(
            get: { controller.sort.key },
            set: { controller.sort = FileSort(key: $0, ascending: controller.sort.ascending) }
        )
    }

    private var currentLocationBinding: Binding<String?> {
        Binding(
            get: {
                pendingLocationID ?? controller.locations.first(where: {
                    controller.currentURL.standardizedFileURL == $0.url.standardizedFileURL
                })?.id
            },
            set: { id in
                guard let location = controller.locations.first(where: { $0.id == id }) else {
                    return
                }
                pendingLocationID = id
                Task {
                    await controller.navigate(to: location)
                    if pendingLocationID == id {
                        pendingLocationID = nil
                    }
                }
            }
        )
    }

    private var pathComponents: [URL] {
        let current = controller.currentURL.standardizedFileURL
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let roots = controller.locations.map { $0.url.standardizedFileURL }
        let root = current.isDescendant(of: home)
            ? home
            : roots
                .filter { current.isDescendant(of: $0) }
                .max { $0.path.count < $1.path.count }
                ?? current

        var components: [URL] = [current]
        var cursor = current
        while cursor != root {
            let parent = cursor.deletingLastPathComponent().standardizedFileURL
            guard parent != cursor, parent.isDescendant(of: root) || parent == root else { break }
            components.append(parent)
            cursor = parent
        }
        return components.reversed()
    }

    private func sortLabel(_ key: FileSort.Key) -> String {
        switch key {
        case .name: model.text("file.sort.name")
        case .size: model.text("file.sort.size")
        case .kind: model.text("file.sort.kind")
        case .modificationDate: model.text("file.sort.modified")
        }
    }

    private func locationIcon(_ kind: FileBrowserLocation.Kind) -> String {
        switch kind {
        case .home: "house"
        case .desktop: "menubar.dock.rectangle"
        case .downloads: "arrow.down.circle"
        case .documents: "doc"
        case .pictures: "photo"
        case .favorite: "star"
        case .volume: "externaldrive"
        }
    }

    private func locationDisplayName(_ location: FileBrowserLocation) -> String {
        switch location.kind {
        case .home: model.text("file.location.home")
        case .desktop: model.text("file.location.desktop")
        case .downloads: model.text("file.location.downloads")
        case .documents: model.text("file.location.documents")
        case .pictures: model.text("file.location.pictures")
        case .favorite, .volume: location.name
        }
    }

    private var nativeColumnTitles: NativeFileColumnTitles {
        NativeFileColumnTitles(
            name: model.text("file.column.name"),
            size: model.text("file.column.size"),
            kind: model.text("file.column.kind"),
            modified: model.text("file.column.modified")
        )
    }

    private var nativeMenuTitles: NativeFileMenuTitles {
        NativeFileMenuTitles(
            open: model.text("file.open"),
            quickLook: model.text("file.quickLook"),
            reveal: model.text("file.reveal"),
            rename: model.text("file.rename"),
            copy: model.text("file.copy"),
            move: model.text("file.move"),
            trash: model.text("file.trash")
        )
    }

    private func performNativeAction(_ action: NativeFileAction, item: LocalFileItem) {
        if !controller.selection.contains(item.id) {
            controller.selection = [item.id]
        }

        switch action {
        case .quickLook:
            quickLookURL = item.url
        case .reveal:
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        case .copy:
            controller.copySelection()
        case .move:
            chooseMoveDestination()
        case .trash:
            requestTrash()
        }
    }

    private func requestTrash() {
        let selected = controller.selectedItems
        guard !selected.isEmpty else { return }
        if selected.count > 1 || selected.contains(where: \.isDirectory) {
            confirmsTrash = true
        } else {
            Task { await controller.trashSelection() }
        }
    }

    private func requestPaste(moving: Bool) {
        Task {
            if await controller.hasPasteConflicts() {
                pendingTransfer = PendingTransfer(kind: .paste(moving: moving))
            } else {
                await controller.paste(
                    moving: moving,
                    conflictResolution: .keepBoth
                )
            }
        }
    }

    private func requestDrop(
        _ urls: [URL],
        to destination: URL,
        moving: Bool = false
    ) {
        Task {
            if await controller.hasConflicts(urls, in: destination) {
                pendingTransfer = PendingTransfer(
                    kind: .drop(
                        urls: urls,
                        destination: destination,
                        moving: moving
                    )
                )
            } else {
                await controller.receiveDrop(
                    urls,
                    to: destination,
                    moving: moving,
                    conflictResolution: .keepBoth
                )
            }
        }
    }

    private func finishTransfer(
        _ transfer: PendingTransfer,
        resolution: FileConflictResolution
    ) {
        pendingTransfer = nil
        Task {
            switch transfer.kind {
            case let .paste(moving):
                await controller.paste(
                    moving: moving,
                    conflictResolution: resolution
                )
            case let .drop(urls, destination, moving):
                await controller.receiveDrop(
                    urls,
                    to: destination,
                    moving: moving,
                    conflictResolution: resolution
                )
            }
        }
    }

    private func chooseFavorite() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = model.text("file.chooseFolder")
        panel.directoryURL = controller.currentURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        controller.addFavorite(url)
        Task { await controller.navigate(to: url) }
    }

    private func chooseMoveDestination() {
        let urls = controller.selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = model.text("file.move")
        panel.directoryURL = controller.currentURL
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        controller.allowAccessForSession(to: destination)
        requestDrop(urls, to: destination, moving: true)
    }

    private struct PendingTransfer: Identifiable {
        enum Kind {
            case paste(moving: Bool)
            case drop(urls: [URL], destination: URL, moving: Bool)
        }

        let id = UUID()
        let kind: Kind
    }
}

private struct NativeFileColumnTitles: Equatable {
    let name: String
    let size: String
    let kind: String
    let modified: String
}

private struct NativeFileMenuTitles: Equatable {
    let open: String
    let quickLook: String
    let reveal: String
    let rename: String
    let copy: String
    let move: String
    let trash: String
}

private enum NativeFileAction {
    case quickLook
    case reveal
    case copy
    case move
    case trash
}

private final class FileTableView: NSTableView {
    var openSelection: (() -> Void)?
    var renameSelection: (() -> Void)?
    var trashSelection: (() -> Void)?
    var menuForRow: ((Int) -> NSMenu?)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            renameSelection?()
        case 49:
            openSelection?()
        case 51 where event.modifierFlags.contains(.command):
            trashSelection?()
        default:
            super.keyDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return nil }
        if !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return menuForRow?(row)
    }
}

private struct NativeFileListView: NSViewRepresentable {
    let items: [LocalFileItem]
    let selection: Set<URL>
    let currentDirectory: URL
    let sort: FileSort
    let columnTitles: NativeFileColumnTitles
    let menuTitles: NativeFileMenuTitles
    let selectionChanged: (Set<URL>) -> Void
    let open: (LocalFileItem) -> Void
    let rename: (LocalFileItem, String) -> Void
    let sortChanged: (FileSort) -> Void
    let performAction: (NativeFileAction, LocalFileItem) -> Void
    let drop: ([URL], URL) -> Void
    let trash: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = FileTableView()
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.style = .fullWidth
        table.selectionHighlightStyle = .regular
        table.usesAlternatingRowBackgroundColors = true
        table.rowSizeStyle = .medium
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.openDoubleClickedItem(_:))
        table.registerForDraggedTypes([.fileURL])

        let name = makeColumn(
            id: FileSort.Key.name.rawValue,
            title: columnTitles.name,
            width: 320,
            minWidth: 150,
            key: .name
        )
        name.resizingMask = .autoresizingMask
        table.addTableColumn(name)
        table.addTableColumn(makeColumn(
            id: FileSort.Key.size.rawValue,
            title: columnTitles.size,
            width: 84,
            minWidth: 64,
            key: .size
        ))
        table.addTableColumn(makeColumn(
            id: FileSort.Key.kind.rawValue,
            title: columnTitles.kind,
            width: 105,
            minWidth: 80,
            key: .kind
        ))
        table.addTableColumn(makeColumn(
            id: FileSort.Key.modificationDate.rawValue,
            title: columnTitles.modified,
            width: 150,
            minWidth: 120,
            key: .modificationDate
        ))

        table.openSelection = { [weak coordinator = context.coordinator] in
            coordinator?.openSelectedItem()
        }
        table.renameSelection = { [weak coordinator = context.coordinator] in
            coordinator?.beginRenamingSelectedItem()
        }
        table.trashSelection = { [weak coordinator = context.coordinator] in
            coordinator?.parent.trash()
        }
        table.menuForRow = { [weak coordinator = context.coordinator] row in
            coordinator?.menu(for: row)
        }
        context.coordinator.table = table

        let scrollView = NSScrollView()
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let table = scrollView.documentView as? FileTableView else { return }
        let coordinator = context.coordinator
        let itemsChanged = coordinator.items != items
        coordinator.parent = self
        coordinator.items = items
        if itemsChanged {
            table.reloadData()
        }
        coordinator.applySelection(selection, to: table)
        coordinator.applySort(sort, to: table)
        updateColumnTitles(in: table)
    }

    private func makeColumn(
        id: String,
        title: String,
        width: CGFloat,
        minWidth: CGFloat,
        key: FileSort.Key
    ) -> NSTableColumn {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        column.minWidth = minWidth
        column.sortDescriptorPrototype = NSSortDescriptor(
            key: key.rawValue,
            ascending: true,
            selector: #selector(NSString.localizedStandardCompare(_:))
        )
        return column
    }

    private func updateColumnTitles(in table: NSTableView) {
        let titles = [
            FileSort.Key.name.rawValue: columnTitles.name,
            FileSort.Key.size.rawValue: columnTitles.size,
            FileSort.Key.kind.rawValue: columnTitles.kind,
            FileSort.Key.modificationDate.rawValue: columnTitles.modified,
        ]
        for column in table.tableColumns {
            column.title = titles[column.identifier.rawValue] ?? column.title
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
        var parent: NativeFileListView
        var items: [LocalFileItem] = []
        weak var table: FileTableView?
        private var synchronizingSelection = false
        private var synchronizingSort = false
        private var editingItem: LocalFileItem?
        private var originalName = ""
        private var cancellingEdit = false
        private var contextItem: LocalFileItem?

        init(parent: NativeFileListView) {
            self.parent = parent
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            items.count
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard let tableColumn, items.indices.contains(row) else { return nil }
            let item = items[row]
            let identifier = tableColumn.identifier
            let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView)
                ?? makeCell(identifier: identifier)

            switch identifier.rawValue {
            case FileSort.Key.name.rawValue:
                cell.imageView?.image = NSWorkspace.shared.icon(forFile: item.url.path)
                cell.textField?.stringValue = item.name
                cell.textField?.toolTip = item.name
                cell.textField?.delegate = self
                cell.objectValue = item.id
            case FileSort.Key.size.rawValue:
                cell.textField?.stringValue = item.isDirectory
                    ? "—"
                    : ByteCountFormatter.string(
                        fromByteCount: item.size ?? 0,
                        countStyle: .file
                    )
                cell.textField?.alignment = .right
            case FileSort.Key.kind.rawValue:
                cell.textField?.stringValue = item.localizedTypeDescription ?? "—"
            case FileSort.Key.modificationDate.rawValue:
                cell.textField?.stringValue = item.modificationDate?.formatted(
                    date: .numeric,
                    time: .shortened
                ) ?? "—"
            default:
                break
            }
            cell.alphaValue = item.isHidden ? 0.58 : 1
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !synchronizingSelection, let table else { return }
            let urls = Set(table.selectedRowIndexes.compactMap { index in
                items.indices.contains(index) ? items[index].id : nil
            })
            parent.selectionChanged(urls)
        }

        func tableView(
            _ tableView: NSTableView,
            sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
        ) {
            guard !synchronizingSort,
                  let descriptor = tableView.sortDescriptors.first,
                  let keyString = descriptor.key,
                  let key = FileSort.Key(rawValue: keyString)
            else { return }
            parent.sortChanged(FileSort(key: key, ascending: descriptor.ascending))
        }

        func tableView(
            _ tableView: NSTableView,
            pasteboardWriterForRow row: Int
        ) -> NSPasteboardWriting? {
            guard items.indices.contains(row) else { return nil }
            return items[row].url as NSURL
        }

        func tableView(
            _ tableView: NSTableView,
            validateDrop info: NSDraggingInfo,
            proposedRow row: Int,
            proposedDropOperation dropOperation: NSTableView.DropOperation
        ) -> NSDragOperation {
            fileURLs(from: info).isEmpty ? [] : .copy
        }

        func tableView(
            _ tableView: NSTableView,
            acceptDrop info: NSDraggingInfo,
            row: Int,
            dropOperation: NSTableView.DropOperation
        ) -> Bool {
            let urls = fileURLs(from: info)
            guard !urls.isEmpty else { return false }
            let destination: URL
            if dropOperation == .on,
               items.indices.contains(row),
               items[row].isBrowsableDirectory {
                destination = items[row].url
            } else {
                destination = parent.currentDirectory
            }
            parent.drop(urls, destination)
            return true
        }

        @objc func openDoubleClickedItem(_ sender: Any?) {
            guard let table else { return }
            let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
            guard items.indices.contains(row) else { return }
            parent.open(items[row])
        }

        func openSelectedItem() {
            guard let table,
                  table.selectedRowIndexes.count == 1,
                  let row = table.selectedRowIndexes.first,
                  items.indices.contains(row)
            else { return }
            parent.open(items[row])
        }

        func beginRenamingSelectedItem() {
            guard let table,
                  table.selectedRowIndexes.count == 1,
                  let row = table.selectedRowIndexes.first,
                  items.indices.contains(row),
                  let cell = table.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView,
                  let field = cell.textField
            else { return }
            beginEditing(field, item: items[row])
        }

        func applySelection(_ selection: Set<URL>, to table: NSTableView) {
            let indexes = IndexSet(items.indices.filter { selection.contains(items[$0].id) })
            guard indexes != table.selectedRowIndexes else { return }
            synchronizingSelection = true
            table.selectRowIndexes(indexes, byExtendingSelection: false)
            synchronizingSelection = false
        }

        func applySort(_ sort: FileSort, to table: NSTableView) {
            guard table.sortDescriptors.first?.key != sort.key.rawValue
                    || table.sortDescriptors.first?.ascending != sort.ascending
            else { return }
            synchronizingSort = true
            table.sortDescriptors = [NSSortDescriptor(key: sort.key.rawValue, ascending: sort.ascending)]
            synchronizingSort = false
        }

        func menu(for row: Int) -> NSMenu? {
            guard items.indices.contains(row) else { return nil }
            contextItem = items[row]
            let menu = NSMenu()
            addItem(parent.menuTitles.open, action: #selector(menuOpen), to: menu)
            addItem(parent.menuTitles.quickLook, action: #selector(menuQuickLook), to: menu)
            addItem(parent.menuTitles.reveal, action: #selector(menuReveal), to: menu)
            menu.addItem(.separator())
            addItem(parent.menuTitles.rename, action: #selector(menuRename), to: menu)
            addItem(parent.menuTitles.copy, action: #selector(menuCopy), to: menu)
            addItem(parent.menuTitles.move, action: #selector(menuMove), to: menu)
            menu.addItem(.separator())
            addItem(parent.menuTitles.trash, action: #selector(menuTrash), to: menu)
            return menu
        }

        @objc private func menuOpen() { withContextItem { parent.open($0) } }
        @objc private func menuQuickLook() { perform(.quickLook) }
        @objc private func menuReveal() { perform(.reveal) }
        @objc private func menuCopy() { perform(.copy) }
        @objc private func menuMove() { perform(.move) }
        @objc private func menuTrash() { perform(.trash) }
        @objc private func menuRename() { beginRenamingSelectedItem() }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                table?.window?.makeFirstResponder(table)
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                cancellingEdit = true
                (control as? NSTextField)?.stringValue = originalName
                table?.window?.makeFirstResponder(table)
                return true
            }
            return false
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  let item = editingItem
            else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            field.isEditable = false
            field.isSelectable = false
            editingItem = nil
            defer { cancellingEdit = false }
            guard !cancellingEdit, !name.isEmpty, name != item.name else {
                field.stringValue = item.name
                return
            }
            parent.rename(item, name)
        }

        private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let field = NSTextField(string: "")
            field.translatesAutoresizingMaskIntoConstraints = false
            field.isBordered = false
            field.drawsBackground = false
            field.isEditable = false
            field.isSelectable = false
            field.focusRingType = .none
            field.lineBreakMode = .byTruncatingMiddle
            field.usesSingleLineMode = true
            cell.textField = field
            cell.addSubview(field)

            if identifier.rawValue == FileSort.Key.name.rawValue {
                let icon = NSImageView()
                icon.translatesAutoresizingMaskIntoConstraints = false
                icon.imageScaling = .scaleProportionallyUpOrDown
                cell.imageView = icon
                cell.addSubview(icon)
                NSLayoutConstraint.activate([
                    icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                    icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    icon.widthAnchor.constraint(equalToConstant: 22),
                    icon.heightAnchor.constraint(equalToConstant: 22),
                    field.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7),
                    field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                    field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            } else {
                NSLayoutConstraint.activate([
                    field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                    field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                    field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }
            return cell
        }

        private func beginEditing(_ field: NSTextField, item: LocalFileItem) {
            editingItem = item
            originalName = item.name
            cancellingEdit = false
            field.isEditable = true
            field.isSelectable = true
            field.stringValue = item.name
            field.window?.makeFirstResponder(field)
            selectBaseName(item.name, in: field)
        }

        private func selectBaseName(_ name: String, in field: NSTextField) {
            DispatchQueue.main.async {
                guard let editor = field.currentEditor() else { return }
                let value = name as NSString
                let pathExtension = value.pathExtension as NSString
                let length = pathExtension.length > 0
                    ? max(0, value.length - pathExtension.length - 1)
                    : value.length
                editor.selectedRange = NSRange(location: 0, length: length)
            }
        }

        private func addItem(_ title: String, action: Selector, to menu: NSMenu) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        private func perform(_ action: NativeFileAction) {
            withContextItem { parent.performAction(action, $0) }
        }

        private func withContextItem(_ action: (LocalFileItem) -> Void) {
            guard let contextItem else { return }
            action(contextItem)
        }

        private func fileURLs(from info: NSDraggingInfo) -> [URL] {
            let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
            return (info.draggingPasteboard.readObjects(
                forClasses: [NSURL.self],
                options: options
            ) as? [URL]) ?? []
        }
    }
}

private final class FileCollectionView: NSCollectionView {
    var openSelection: (() -> Void)?
    var renameSelection: (() -> Void)?
    var trashSelection: (() -> Void)?
    var menuForItem: ((IndexPath) -> NSMenu?)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            renameSelection?()
        case 49:
            openSelection?()
        case 51 where event.modifierFlags.contains(.command):
            trashSelection?()
        default:
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clickedIndexPath = indexPathForItem(at: point)
        super.mouseDown(with: event)
        if event.clickCount == 2, clickedIndexPath != nil {
            openSelection?()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let indexPath = indexPathForItem(at: point) else { return nil }
        if !selectionIndexPaths.contains(indexPath) {
            selectionIndexPaths = [indexPath]
            delegate?.collectionView?(self, didSelectItemsAt: [indexPath])
        }
        return menuForItem?(indexPath)
    }
}

private final class NativeFileCollectionItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("NativeFileCollectionItem")
    private static let thumbnailCache = NSCache<NSString, NSImage>()
    private let iconSelectionBackground = NSView()
    private let iconView = NSImageView()
    private let nameField = NSTextField(string: "")
    private var thumbnailTask: Task<Void, Never>?
    private var representedURL: URL?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true

        iconSelectionBackground.translatesAutoresizingMaskIntoConstraints = false
        iconSelectionBackground.wantsLayer = true
        iconSelectionBackground.layer?.cornerRadius = 10

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 5
        iconView.layer?.masksToBounds = true
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.isBordered = false
        nameField.drawsBackground = false
        nameField.isEditable = false
        nameField.isSelectable = false
        nameField.focusRingType = .none
        nameField.alignment = .center
        nameField.lineBreakMode = .byTruncatingMiddle
        nameField.maximumNumberOfLines = 2
        nameField.cell?.wraps = true
        nameField.wantsLayer = true
        nameField.layer?.cornerRadius = 5
        nameField.layer?.masksToBounds = true

        view.addSubview(iconSelectionBackground)
        view.addSubview(iconView)
        view.addSubview(nameField)
        imageView = iconView
        textField = nameField
        NSLayoutConstraint.activate([
            iconSelectionBackground.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
            iconSelectionBackground.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconSelectionBackground.widthAnchor.constraint(equalToConstant: 88),
            iconSelectionBackground.heightAnchor.constraint(equalToConstant: 88),
            iconView.centerXAnchor.constraint(equalTo: iconSelectionBackground.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconSelectionBackground.centerYAnchor),
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 72),
            iconView.heightAnchor.constraint(equalToConstant: 72),
            nameField.topAnchor.constraint(equalTo: iconSelectionBackground.bottomAnchor, constant: 4),
            nameField.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            nameField.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 5),
            nameField.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -5),
            nameField.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -5),
        ])
        updateSelectionAppearance()
    }

    override var isSelected: Bool {
        didSet { updateSelectionAppearance() }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailTask?.cancel()
        thumbnailTask = nil
        representedURL = nil
        iconView.image = nil
        nameField.delegate = nil
    }

    func configure(with item: LocalFileItem, delegate: NSTextFieldDelegate) {
        representedObject = item
        representedURL = item.url
        thumbnailTask?.cancel()
        iconView.image = NSWorkspace.shared.icon(forFile: item.url.path)
        nameField.stringValue = item.name
        nameField.toolTip = item.name
        nameField.delegate = delegate
        view.alphaValue = item.isHidden ? 0.58 : 1
        updateSelectionAppearance()
        loadThumbnail(for: item)
    }

    func beginEditing() -> NSTextField {
        nameField.isEditable = true
        nameField.isSelectable = true
        updateSelectionAppearance()
        nameField.window?.makeFirstResponder(nameField)
        return nameField
    }

    func finishEditing() {
        nameField.isEditable = false
        nameField.isSelectable = false
        updateSelectionAppearance()
    }

    private func updateSelectionAppearance() {
        guard isViewLoaded else { return }
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.borderColor = NSColor.clear.cgColor
        iconSelectionBackground.layer?.backgroundColor = isSelected
            ? NSColor.quaternaryLabelColor.cgColor
            : NSColor.clear.cgColor

        if nameField.isEditable {
            nameField.backgroundColor = .textBackgroundColor
            nameField.textColor = .labelColor
            nameField.layer?.borderColor = NSColor.controlAccentColor.cgColor
            nameField.layer?.borderWidth = 2
            nameField.drawsBackground = true
        } else if isSelected {
            nameField.backgroundColor = .controlAccentColor
            nameField.textColor = .white
            nameField.layer?.borderColor = NSColor.clear.cgColor
            nameField.layer?.borderWidth = 0
            nameField.drawsBackground = true
        } else {
            nameField.backgroundColor = .clear
            nameField.textColor = .labelColor
            nameField.layer?.borderColor = NSColor.clear.cgColor
            nameField.layer?.borderWidth = 0
            nameField.drawsBackground = false
        }
    }

    private func loadThumbnail(for item: LocalFileItem) {
        guard !item.isBrowsableDirectory else { return }
        let cacheKey = thumbnailCacheKey(for: item)
        if let cached = Self.thumbnailCache.object(forKey: cacheKey) {
            iconView.image = cached
            return
        }

        let url = item.url
        thumbnailTask = Task { [weak self] in
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: 144, height: 144),
                scale: NSScreen.main?.backingScaleFactor ?? 2,
                representationTypes: .thumbnail
            )
            guard let representation = try? await QLThumbnailGenerator.shared
                .generateBestRepresentation(for: request),
                  !Task.isCancelled,
                  self?.representedURL == url
            else { return }
            let image = representation.nsImage
            Self.thumbnailCache.setObject(image, forKey: cacheKey)
            self?.iconView.image = image
        }
    }

    private func thumbnailCacheKey(for item: LocalFileItem) -> NSString {
        let modification = item.modificationDate?.timeIntervalSinceReferenceDate ?? 0
        return "\(item.url.path)|\(modification)" as NSString
    }
}

private struct NativeFileIconView: NSViewRepresentable {
    let items: [LocalFileItem]
    let selection: Set<URL>
    let currentDirectory: URL
    let menuTitles: NativeFileMenuTitles
    let selectionChanged: (Set<URL>) -> Void
    let open: (LocalFileItem) -> Void
    let rename: (LocalFileItem, String) -> Void
    let performAction: (NativeFileAction, LocalFileItem) -> Void
    let drop: ([URL], URL) -> Void
    let trash: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 112, height: 132)
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        layout.scrollDirection = .vertical

        let collection = FileCollectionView()
        collection.collectionViewLayout = layout
        collection.dataSource = context.coordinator
        collection.delegate = context.coordinator
        collection.isSelectable = true
        collection.allowsEmptySelection = true
        collection.allowsMultipleSelection = true
        collection.backgroundColors = [.textBackgroundColor]
        collection.register(
            NativeFileCollectionItem.self,
            forItemWithIdentifier: NativeFileCollectionItem.reuseIdentifier
        )
        collection.registerForDraggedTypes([.fileURL])
        collection.openSelection = { [weak coordinator = context.coordinator] in
            coordinator?.openSelectedItem()
        }
        collection.renameSelection = { [weak coordinator = context.coordinator] in
            coordinator?.beginRenamingSelectedItem()
        }
        collection.trashSelection = { [weak coordinator = context.coordinator] in
            coordinator?.parent.trash()
        }
        collection.menuForItem = { [weak coordinator = context.coordinator] indexPath in
            coordinator?.menu(for: indexPath)
        }
        context.coordinator.collection = collection

        let scrollView = NSScrollView()
        scrollView.documentView = collection
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let collection = scrollView.documentView as? FileCollectionView else { return }
        let coordinator = context.coordinator
        let itemsChanged = coordinator.items != items
        coordinator.parent = self
        coordinator.items = items
        if itemsChanged {
            collection.reloadData()
        }
        coordinator.applySelection(selection, to: collection)
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate, NSTextFieldDelegate {
        var parent: NativeFileIconView
        var items: [LocalFileItem] = []
        weak var collection: FileCollectionView?
        private var synchronizingSelection = false
        private var editingItem: LocalFileItem?
        private var editingCollectionItem: NativeFileCollectionItem?
        private var originalName = ""
        private var cancellingEdit = false
        private var contextItem: LocalFileItem?

        init(parent: NativeFileIconView) {
            self.parent = parent
        }

        func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

        func collectionView(
            _ collectionView: NSCollectionView,
            numberOfItemsInSection section: Int
        ) -> Int {
            items.count
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            itemForRepresentedObjectAt indexPath: IndexPath
        ) -> NSCollectionViewItem {
            let collectionItem = collectionView.makeItem(
                withIdentifier: NativeFileCollectionItem.reuseIdentifier,
                for: indexPath
            ) as! NativeFileCollectionItem
            if items.indices.contains(indexPath.item) {
                collectionItem.configure(with: items[indexPath.item], delegate: self)
            }
            return collectionItem
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            didSelectItemsAt indexPaths: Set<IndexPath>
        ) {
            selectionChanged(in: collectionView)
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            didDeselectItemsAt indexPaths: Set<IndexPath>
        ) {
            selectionChanged(in: collectionView)
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            pasteboardWriterForItemAt indexPath: IndexPath
        ) -> NSPasteboardWriting? {
            guard items.indices.contains(indexPath.item) else { return nil }
            return items[indexPath.item].url as NSURL
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            validateDrop draggingInfo: NSDraggingInfo,
            proposedIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
            dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
        ) -> NSDragOperation {
            fileURLs(from: draggingInfo).isEmpty ? [] : .copy
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            acceptDrop draggingInfo: NSDraggingInfo,
            indexPath: IndexPath,
            dropOperation: NSCollectionView.DropOperation
        ) -> Bool {
            let urls = fileURLs(from: draggingInfo)
            guard !urls.isEmpty else { return false }
            let destination: URL
            if dropOperation == .on,
               items.indices.contains(indexPath.item),
               items[indexPath.item].isBrowsableDirectory {
                destination = items[indexPath.item].url
            } else {
                destination = parent.currentDirectory
            }
            parent.drop(urls, destination)
            return true
        }

        func applySelection(_ selection: Set<URL>, to collection: NSCollectionView) {
            let indexPaths = Set(items.indices.compactMap { index in
                selection.contains(items[index].id)
                    ? IndexPath(item: index, section: 0)
                    : nil
            })
            guard indexPaths != collection.selectionIndexPaths else { return }
            synchronizingSelection = true
            collection.selectionIndexPaths = indexPaths
            synchronizingSelection = false
        }

        func openSelectedItem() {
            guard let collection,
                  collection.selectionIndexPaths.count == 1,
                  let indexPath = collection.selectionIndexPaths.first,
                  items.indices.contains(indexPath.item)
            else { return }
            parent.open(items[indexPath.item])
        }

        func beginRenamingSelectedItem() {
            guard let collection,
                  collection.selectionIndexPaths.count == 1,
                  let indexPath = collection.selectionIndexPaths.first,
                  items.indices.contains(indexPath.item),
                  let collectionItem = collection.item(at: indexPath) as? NativeFileCollectionItem
            else { return }
            let item = items[indexPath.item]
            editingItem = item
            editingCollectionItem = collectionItem
            originalName = item.name
            cancellingEdit = false
            let field = collectionItem.beginEditing()
            selectBaseName(item.name, in: field)
        }

        func menu(for indexPath: IndexPath) -> NSMenu? {
            guard items.indices.contains(indexPath.item) else { return nil }
            contextItem = items[indexPath.item]
            let menu = NSMenu()
            addItem(parent.menuTitles.open, action: #selector(menuOpen), to: menu)
            addItem(parent.menuTitles.quickLook, action: #selector(menuQuickLook), to: menu)
            addItem(parent.menuTitles.reveal, action: #selector(menuReveal), to: menu)
            menu.addItem(.separator())
            addItem(parent.menuTitles.rename, action: #selector(menuRename), to: menu)
            addItem(parent.menuTitles.copy, action: #selector(menuCopy), to: menu)
            addItem(parent.menuTitles.move, action: #selector(menuMove), to: menu)
            menu.addItem(.separator())
            addItem(parent.menuTitles.trash, action: #selector(menuTrash), to: menu)
            return menu
        }

        @objc private func menuOpen() { withContextItem { parent.open($0) } }
        @objc private func menuQuickLook() { perform(.quickLook) }
        @objc private func menuReveal() { perform(.reveal) }
        @objc private func menuCopy() { perform(.copy) }
        @objc private func menuMove() { perform(.move) }
        @objc private func menuTrash() { perform(.trash) }
        @objc private func menuRename() { beginRenamingSelectedItem() }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                collection?.window?.makeFirstResponder(collection)
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                cancellingEdit = true
                (control as? NSTextField)?.stringValue = originalName
                collection?.window?.makeFirstResponder(collection)
                return true
            }
            return false
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  let item = editingItem
            else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            editingCollectionItem?.finishEditing()
            editingItem = nil
            editingCollectionItem = nil
            defer { cancellingEdit = false }
            guard !cancellingEdit, !name.isEmpty, name != item.name else {
                field.stringValue = item.name
                return
            }
            parent.rename(item, name)
        }

        private func selectionChanged(in collectionView: NSCollectionView) {
            guard !synchronizingSelection else { return }
            let urls = Set(collectionView.selectionIndexPaths.compactMap { indexPath in
                items.indices.contains(indexPath.item) ? items[indexPath.item].id : nil
            })
            parent.selectionChanged(urls)
        }

        private func selectBaseName(_ name: String, in field: NSTextField) {
            DispatchQueue.main.async {
                guard let editor = field.currentEditor() else { return }
                let value = name as NSString
                let pathExtension = value.pathExtension as NSString
                let length = pathExtension.length > 0
                    ? max(0, value.length - pathExtension.length - 1)
                    : value.length
                editor.selectedRange = NSRange(location: 0, length: length)
            }
        }

        private func addItem(_ title: String, action: Selector, to menu: NSMenu) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        private func perform(_ action: NativeFileAction) {
            withContextItem { parent.performAction(action, $0) }
        }

        private func withContextItem(_ action: (LocalFileItem) -> Void) {
            guard let contextItem else { return }
            action(contextItem)
        }

        private func fileURLs(from info: NSDraggingInfo) -> [URL] {
            let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
            return (info.draggingPasteboard.readObjects(
                forClasses: [NSURL.self],
                options: options
            ) as? [URL]) ?? []
        }
    }
}

private struct FileDetailsPane: View {
    @ObservedObject var model: AppModel
    let item: LocalFileItem
    let open: () -> Void
    let quickLook: () -> Void
    let reveal: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                FileThumbnail(url: item.url)
                    .frame(width: 112, height: 112)
                    .padding(.top, 28)

                VStack(spacing: 5) {
                    Text(item.name)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                    Text(item.localizedTypeDescription ?? "—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button(action: open) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .help(model.text("file.open"))
                    Button(action: quickLook) {
                        Image(systemName: "eye")
                    }
                    .help(model.text("file.quickLook"))
                    Button(action: reveal) {
                        Image(systemName: "folder")
                    }
                    .help(model.text("file.reveal"))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Divider()

                VStack(spacing: 11) {
                    detailRow(model.text("file.detail.size"), item.isDirectory ? "—" : formattedSize)
                    detailRow(model.text("file.detail.modified"), formattedDate(item.modificationDate))
                    detailRow(model.text("file.detail.created"), formattedDate(item.creationDate))
                    detailRow(model.text("file.detail.path"), item.url.path)
                }
                .font(.caption)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
    }

    private var formattedSize: String {
        guard let size = item.size else { return "—" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}

private struct FileThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .scaledToFit()
            }
        }
        .task(id: url) {
            image = nil
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: 224, height: 224),
                scale: NSScreen.main?.backingScaleFactor ?? 2,
                representationTypes: .all
            )
            image = try? await QLThumbnailGenerator.shared
                .generateBestRepresentation(for: request)
                .nsImage
        }
    }
}

private extension URL {
    func isDescendant(of ancestor: URL) -> Bool {
        let childPath = standardizedFileURL.pathComponents
        let ancestorPath = ancestor.standardizedFileURL.pathComponents
        guard ancestorPath.count <= childPath.count else { return false }
        return Array(childPath.prefix(ancestorPath.count)) == ancestorPath
    }
}
