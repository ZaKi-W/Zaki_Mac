import Foundation

struct LocalFileItem: Identifiable, Hashable, Sendable {
    let id: URL
    let url: URL
    let name: String
    let isDirectory: Bool
    let isPackage: Bool
    let isSymbolicLink: Bool
    let isHidden: Bool
    let size: Int64?
    let allocatedSize: Int64?
    let creationDate: Date?
    let modificationDate: Date?
    let typeIdentifier: String?
    let localizedTypeDescription: String?
    let isReadable: Bool
    let isWritable: Bool

    init(
        url: URL,
        name: String,
        isDirectory: Bool,
        isPackage: Bool,
        isSymbolicLink: Bool,
        isHidden: Bool,
        size: Int64?,
        allocatedSize: Int64?,
        creationDate: Date?,
        modificationDate: Date?,
        typeIdentifier: String?,
        localizedTypeDescription: String?,
        isReadable: Bool,
        isWritable: Bool
    ) {
        let standardizedURL = url.standardizedFileURL
        id = standardizedURL
        self.url = standardizedURL
        self.name = name
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.isSymbolicLink = isSymbolicLink
        self.isHidden = isHidden
        self.size = size
        self.allocatedSize = allocatedSize
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.typeIdentifier = typeIdentifier
        self.localizedTypeDescription = localizedTypeDescription
        self.isReadable = isReadable
        self.isWritable = isWritable
    }

    var isBrowsableDirectory: Bool {
        isDirectory && !isPackage && !isSymbolicLink
    }
}

struct FileBrowserLocation: Identifiable, Codable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case home
        case desktop
        case downloads
        case documents
        case pictures
        case favorite
        case volume
    }

    let id: String
    var name: String
    var url: URL
    var kind: Kind

    init(id: String? = nil, name: String, url: URL, kind: Kind) {
        let standardizedURL = url.standardizedFileURL
        self.id = id ?? "\(kind.rawValue):\(standardizedURL.path)"
        self.name = name
        self.url = standardizedURL
        self.kind = kind
    }
}

struct FileSort: Codable, Equatable, Hashable, Sendable {
    enum Key: String, Codable, CaseIterable, Identifiable, Sendable {
        case name
        case size
        case kind
        case modificationDate

        var id: Self { self }
    }

    var key: Key
    var ascending: Bool

    static let `default` = FileSort(key: .name, ascending: true)
}

enum FileBrowserViewMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case list
    case icons

    var id: Self { self }
}

enum FileConflictResolution: String, Codable, CaseIterable, Identifiable, Sendable {
    case replace
    case keepBoth
    case skip
    case cancel

    var id: Self { self }
}

enum FileClipboardOperation: String, Codable, Sendable {
    case copy
    case move
}

struct FileClipboard: Equatable, Sendable {
    var urls: [URL]
    var operation: FileClipboardOperation
}

struct FilePasteRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let moving: Bool
}

enum FileOperationKind: String, Sendable {
    case createFile
    case createFolder
    case rename
    case copy
    case move
    case trash
    case restore
}

struct FileOperationFailure: Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceURL: URL
    let destinationURL: URL?
    let message: String

    init(sourceURL: URL, destinationURL: URL? = nil, message: String) {
        id = UUID()
        self.sourceURL = sourceURL.standardizedFileURL
        self.destinationURL = destinationURL?.standardizedFileURL
        self.message = message
    }
}

struct FileOperationResult: Equatable, Sendable {
    var kind: FileOperationKind
    var completedURLs: [URL]
    var skippedURLs: [URL]
    var failures: [FileOperationFailure]

    static func empty(_ kind: FileOperationKind) -> Self {
        FileOperationResult(kind: kind, completedURLs: [], skippedURLs: [], failures: [])
    }

    var isSuccessful: Bool { failures.isEmpty }
}

struct TrashedFile: Identifiable, Equatable, Sendable {
    let id: UUID
    let originalURL: URL
    let trashedURL: URL

    init(originalURL: URL, trashedURL: URL) {
        id = UUID()
        self.originalURL = originalURL.standardizedFileURL
        self.trashedURL = trashedURL.standardizedFileURL
    }
}

struct TrashOperation: Identifiable, Equatable, Sendable {
    let id: UUID
    let files: [TrashedFile]
    let createdAt: Date

    init(id: UUID = UUID(), files: [TrashedFile], createdAt: Date = .now) {
        self.id = id
        self.files = files
        self.createdAt = createdAt
    }
}

enum LocalFileServiceError: LocalizedError, Equatable, Sendable {
    case invalidName
    case itemNotFound(URL)
    case destinationExists(URL)
    case notDirectory(URL)
    case operationCancelled

    var errorDescription: String? {
        switch self {
        case .invalidName:
            "The name cannot be empty or contain a slash."
        case let .itemNotFound(url):
            "The item no longer exists: \(url.lastPathComponent)"
        case let .destinationExists(url):
            "An item named \(url.lastPathComponent) already exists."
        case let .notDirectory(url):
            "The destination is not a folder: \(url.lastPathComponent)"
        case .operationCancelled:
            "The operation was cancelled."
        }
    }
}
