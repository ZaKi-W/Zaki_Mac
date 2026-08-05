import Foundation

actor LocalFileService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func contents(of directory: URL, includingHidden: Bool) throws -> [LocalFileItem] {
        try requireDirectory(directory)
        let options: FileManager.DirectoryEnumerationOptions = includingHidden ? [] : [.skipsHiddenFiles]
        return try fileManager
            .contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Self.resourceKeys,
                options: options
            )
            .compactMap { try? makeItem(at: $0) }
    }

    func item(at url: URL) throws -> LocalFileItem {
        guard fileManager.fileExists(atPath: url.path) else {
            throw LocalFileServiceError.itemNotFound(url)
        }
        return try makeItem(at: url)
    }

    func searchItems(
        at urls: [URL],
        under root: URL,
        includingHidden: Bool
    ) -> [LocalFileItem] {
        let root = root.standardizedFileURL
        return uniqueURLs(urls).compactMap { url in
            guard isEligibleSearchResult(url, under: root, includingHidden: includingHidden) else {
                return nil
            }
            return try? makeItem(at: url)
        }
    }

    func search(
        named query: String,
        under directory: URL,
        includingHidden: Bool,
        limit: Int = 1_000
    ) async throws -> [LocalFileItem] {
        try requireDirectory(directory)
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }

        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !includingHidden {
            options.insert(.skipsHiddenFiles)
        }
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: Self.resourceKeys,
            options: options,
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var matches: [LocalFileItem] = []
        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            guard let item = try? makeItem(at: url) else { continue }
            if item.isSymbolicLink || item.isPackage {
                enumerator.skipDescendants()
            }
            if item.name.localizedStandardContains(normalizedQuery) {
                matches.append(item)
                if matches.count >= limit { break }
            }
        }
        return matches
    }

    func createFolder(named name: String, in directory: URL) throws -> LocalFileItem {
        try requireDirectory(directory)
        let validName = try validatedName(name)
        let destination = directory.appendingPathComponent(validName, isDirectory: true)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw LocalFileServiceError.destinationExists(destination)
        }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        return try makeItem(at: destination)
    }

    func createFile(named name: String, in directory: URL) throws -> LocalFileItem {
        try requireDirectory(directory)
        let validName = try validatedName(name)
        let destination = directory.appendingPathComponent(validName, isDirectory: false)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw LocalFileServiceError.destinationExists(destination)
        }
        guard fileManager.createFile(atPath: destination.path, contents: Data()) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return try makeItem(at: destination)
    }

    func rename(_ source: URL, to name: String) throws -> LocalFileItem {
        guard fileManager.fileExists(atPath: source.path) else {
            throw LocalFileServiceError.itemNotFound(source)
        }
        let validName = try validatedName(name)
        let destination = source.deletingLastPathComponent().appendingPathComponent(validName)
        if source.standardizedFileURL == destination.standardizedFileURL {
            return try makeItem(at: source)
        }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw LocalFileServiceError.destinationExists(destination)
        }
        try fileManager.moveItem(at: source, to: destination)
        return try makeItem(at: destination)
    }

    func hasConflicts(_ sources: [URL], in destinationDirectory: URL) throws -> Bool {
        try requireDirectory(destinationDirectory)
        return sources.contains {
            let destination = destinationDirectory.appendingPathComponent($0.lastPathComponent)
            return destination.standardizedFileURL != $0.standardizedFileURL
                && fileManager.fileExists(atPath: destination.path)
        }
    }

    func copy(
        _ sources: [URL],
        to destinationDirectory: URL,
        conflictResolution: FileConflictResolution
    ) throws -> FileOperationResult {
        try transfer(
            sources,
            to: destinationDirectory,
            moving: false,
            conflictResolution: conflictResolution
        )
    }

    func move(
        _ sources: [URL],
        to destinationDirectory: URL,
        conflictResolution: FileConflictResolution
    ) throws -> FileOperationResult {
        try transfer(
            sources,
            to: destinationDirectory,
            moving: true,
            conflictResolution: conflictResolution
        )
    }

    func trash(_ urls: [URL]) -> (FileOperationResult, TrashOperation?) {
        var result = FileOperationResult.empty(.trash)
        var trashedFiles: [TrashedFile] = []

        for url in uniqueURLs(urls) {
            do {
                guard fileManager.fileExists(atPath: url.path) else {
                    throw LocalFileServiceError.itemNotFound(url)
                }
                var resultingURL: NSURL?
                try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
                guard let trashedURL = resultingURL as URL? else {
                    throw CocoaError(.fileNoSuchFile)
                }
                result.completedURLs.append(url.standardizedFileURL)
                trashedFiles.append(TrashedFile(originalURL: url, trashedURL: trashedURL))
            } catch {
                result.failures.append(
                    FileOperationFailure(sourceURL: url, message: error.localizedDescription)
                )
            }
        }

        let operation = trashedFiles.isEmpty ? nil : TrashOperation(files: trashedFiles)
        return (result, operation)
    }

    func restore(
        _ operation: TrashOperation,
        conflictResolution: FileConflictResolution = .keepBoth
    ) -> FileOperationResult {
        var result = FileOperationResult.empty(.restore)

        for file in operation.files {
            do {
                guard fileManager.fileExists(atPath: file.trashedURL.path) else {
                    throw LocalFileServiceError.itemNotFound(file.trashedURL)
                }
                let resolution = try resolvedDestination(
                    preferred: file.originalURL,
                    conflictResolution: conflictResolution
                )
                guard let destination = resolution.url else {
                    result.skippedURLs.append(file.trashedURL)
                    if conflictResolution == .cancel { break }
                    continue
                }
                do {
                    try fileManager.createDirectory(
                        at: destination.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try fileManager.moveItem(at: file.trashedURL, to: destination)
                } catch {
                    recoverDisplacedItem(resolution.displaced, failedDestination: destination)
                    throw error
                }
                result.completedURLs.append(destination.standardizedFileURL)
            } catch {
                result.failures.append(
                    FileOperationFailure(
                        sourceURL: file.trashedURL,
                        destinationURL: file.originalURL,
                        message: error.localizedDescription
                    )
                )
            }
        }
        return result
    }

    private func transfer(
        _ sources: [URL],
        to destinationDirectory: URL,
        moving: Bool,
        conflictResolution: FileConflictResolution
    ) throws -> FileOperationResult {
        try requireDirectory(destinationDirectory)
        var result = FileOperationResult.empty(moving ? .move : .copy)

        for source in uniqueURLs(sources) {
            do {
                guard fileManager.fileExists(atPath: source.path) else {
                    throw LocalFileServiceError.itemNotFound(source)
                }
                let preferred = destinationDirectory.appendingPathComponent(source.lastPathComponent)
                if preferred.standardizedFileURL == source.standardizedFileURL {
                    if moving {
                        result.skippedURLs.append(source.standardizedFileURL)
                        continue
                    }
                    let duplicate = availableCopyURL(for: preferred)
                    try fileManager.copyItem(at: source, to: duplicate)
                    result.completedURLs.append(duplicate.standardizedFileURL)
                    continue
                }
                let resolution = try resolvedDestination(
                    preferred: preferred,
                    conflictResolution: conflictResolution
                )
                guard let destination = resolution.url else {
                    result.skippedURLs.append(source.standardizedFileURL)
                    if conflictResolution == .cancel { break }
                    continue
                }
                do {
                    if moving {
                        try fileManager.moveItem(at: source, to: destination)
                    } else {
                        try fileManager.copyItem(at: source, to: destination)
                    }
                } catch {
                    recoverDisplacedItem(resolution.displaced, failedDestination: destination)
                    throw error
                }
                result.completedURLs.append(destination.standardizedFileURL)
            } catch {
                result.failures.append(
                    FileOperationFailure(
                        sourceURL: source,
                        destinationURL: destinationDirectory,
                        message: error.localizedDescription
                    )
                )
            }
        }
        return result
    }

    private func resolvedDestination(
        preferred: URL,
        conflictResolution: FileConflictResolution
    ) throws -> (url: URL?, displaced: TrashedFile?) {
        guard fileManager.fileExists(atPath: preferred.path) else {
            return (preferred, nil)
        }

        switch conflictResolution {
        case .replace:
            var resultingURL: NSURL?
            try fileManager.trashItem(at: preferred, resultingItemURL: &resultingURL)
            guard let trashedURL = resultingURL as URL? else {
                throw CocoaError(.fileNoSuchFile)
            }
            return (
                preferred,
                TrashedFile(originalURL: preferred, trashedURL: trashedURL)
            )
        case .keepBoth:
            return (availableCopyURL(for: preferred), nil)
        case .skip, .cancel:
            return (nil, nil)
        }
    }

    private func recoverDisplacedItem(_ displaced: TrashedFile?, failedDestination: URL) {
        guard let displaced else { return }
        if fileManager.fileExists(atPath: failedDestination.path) {
            var ignoredURL: NSURL?
            try? fileManager.trashItem(at: failedDestination, resultingItemURL: &ignoredURL)
        }
        guard !fileManager.fileExists(atPath: displaced.originalURL.path) else { return }
        try? fileManager.createDirectory(
            at: displaced.originalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? fileManager.moveItem(at: displaced.trashedURL, to: displaced.originalURL)
    }

    private func availableCopyURL(for preferred: URL) -> URL {
        let directory = preferred.deletingLastPathComponent()
        let extensionName = preferred.pathExtension
        let baseName = extensionName.isEmpty
            ? preferred.lastPathComponent
            : preferred.deletingPathExtension().lastPathComponent

        for index in 2...10_000 {
            let suffix = index == 2 ? " copy" : " copy \(index)"
            var candidate = directory.appendingPathComponent(baseName + suffix)
            if !extensionName.isEmpty {
                candidate.appendPathExtension(extensionName)
            }
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return directory.appendingPathComponent(baseName + " copy \(UUID().uuidString)")
    }

    private func makeItem(at url: URL) throws -> LocalFileItem {
        let values = try url.resourceValues(forKeys: Set(Self.resourceKeys))
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let isSymbolicLink = attributes?[.type] as? FileAttributeType == .typeSymbolicLink
        let isDirectory = !isSymbolicLink && (values.isDirectory ?? false)
        let name = values.name ?? url.lastPathComponent

        return LocalFileItem(
            url: url,
            name: name,
            isDirectory: isDirectory,
            isPackage: values.isPackage ?? false,
            isSymbolicLink: isSymbolicLink,
            isHidden: values.isHidden ?? name.hasPrefix("."),
            size: values.fileSize.map(Int64.init),
            allocatedSize: values.totalFileAllocatedSize.map(Int64.init),
            creationDate: values.creationDate,
            modificationDate: values.contentModificationDate,
            typeIdentifier: values.typeIdentifier,
            localizedTypeDescription: values.localizedTypeDescription,
            isReadable: values.isReadable ?? fileManager.isReadableFile(atPath: url.path),
            isWritable: values.isWritable ?? fileManager.isWritableFile(atPath: url.path)
        )
    }

    private func isEligibleSearchResult(
        _ candidate: URL,
        under root: URL,
        includingHidden: Bool
    ) -> Bool {
        let candidate = candidate.standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate != root, candidate.path.hasPrefix(rootPath) else { return false }

        var cursor = candidate
        while cursor != root {
            let values = try? cursor.resourceValues(forKeys: [
                .isPackageKey,
                .isHiddenKey,
                .nameKey,
            ])
            let name = values?.name ?? cursor.lastPathComponent
            if !includingHidden, values?.isHidden == true || name.hasPrefix(".") {
                return false
            }

            if cursor != candidate {
                let attributes = try? fileManager.attributesOfItem(atPath: cursor.path)
                if values?.isPackage == true
                    || attributes?[.type] as? FileAttributeType == .typeSymbolicLink {
                    return false
                }
            }

            let parent = cursor.deletingLastPathComponent().standardizedFileURL
            guard parent != cursor else { return false }
            cursor = parent
        }
        return true
    }

    private func requireDirectory(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw LocalFileServiceError.itemNotFound(url)
        }
        guard isDirectory.boolValue else {
            throw LocalFileServiceError.notDirectory(url)
        }
    }

    private func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ".", trimmed != "..", !trimmed.contains("/") else {
            throw LocalFileServiceError.invalidName
        }
        return trimmed
    }

    private func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen: Set<URL> = []
        return urls.compactMap {
            let url = $0.standardizedFileURL
            return seen.insert(url).inserted ? url : nil
        }
    }

    private static let resourceKeys: [URLResourceKey] = [
        .nameKey,
        .isDirectoryKey,
        .isPackageKey,
        .isSymbolicLinkKey,
        .isHiddenKey,
        .fileSizeKey,
        .totalFileAllocatedSizeKey,
        .creationDateKey,
        .contentModificationDateKey,
        .typeIdentifierKey,
        .localizedTypeDescriptionKey,
        .isReadableKey,
        .isWritableKey,
    ]
}
