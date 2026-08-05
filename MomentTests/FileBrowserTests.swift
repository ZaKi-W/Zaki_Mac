import Foundation
import XCTest
@testable import Moment

final class LocalFileServiceTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testListingSearchAndCoreOperations() async throws {
        let service = LocalFileService()
        let visible = temporaryDirectory.appendingPathComponent("notes.txt")
        let hidden = temporaryDirectory.appendingPathComponent(".private.txt")
        try Data("notes".utf8).write(to: visible)
        try Data("private".utf8).write(to: hidden)

        let visibleItems = try await service.contents(
            of: temporaryDirectory,
            includingHidden: false
        )
        XCTAssertEqual(visibleItems.map(\.name), ["notes.txt"])

        let allItems = try await service.contents(
            of: temporaryDirectory,
            includingHidden: true
        )
        XCTAssertEqual(Set(allItems.map(\.name)), ["notes.txt", ".private.txt"])

        let createdFile = try await service.createFile(
            named: "draft.md",
            in: temporaryDirectory
        )
        XCTAssertFalse(createdFile.isDirectory)
        XCTAssertEqual(createdFile.name, "draft.md")
        XCTAssertEqual(try Data(contentsOf: createdFile.url), Data())

        let created = try await service.createFolder(
            named: "Archive",
            in: temporaryDirectory
        )
        let renamed = try await service.rename(created.url, to: "Filed")
        XCTAssertTrue(renamed.isBrowsableDirectory)
        XCTAssertEqual(renamed.name, "Filed")

        let firstCopy = try await service.copy(
            [visible],
            to: renamed.url,
            conflictResolution: .keepBoth
        )
        XCTAssertEqual(firstCopy.completedURLs.map(\.lastPathComponent), ["notes.txt"])

        let secondCopy = try await service.copy(
            [visible],
            to: renamed.url,
            conflictResolution: .keepBoth
        )
        XCTAssertEqual(secondCopy.completedURLs.map(\.lastPathComponent), ["notes copy.txt"])

        let skipped = try await service.copy(
            [visible],
            to: renamed.url,
            conflictResolution: .skip
        )
        XCTAssertEqual(skipped.skippedURLs, [visible.standardizedFileURL])

        let nested = renamed.url.appendingPathComponent("project-needle.md")
        try Data().write(to: nested)
        let matches = try await service.search(
            named: "needle",
            under: temporaryDirectory,
            includingHidden: false
        )
        XCTAssertEqual(matches.map(\.name), ["project-needle.md"])
    }

    func testTrashAndRestoreRoundTrip() async throws {
        let service = LocalFileService()
        let source = temporaryDirectory.appendingPathComponent("recover-me.txt")
        try Data("recover".utf8).write(to: source)

        let (trashResult, operation) = await service.trash([source])
        XCTAssertTrue(trashResult.failures.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))

        let restoreOperation = try XCTUnwrap(operation)
        let restoreResult = await service.restore(
            restoreOperation,
            conflictResolution: .keepBoth
        )

        XCTAssertTrue(restoreResult.failures.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
}

@MainActor
final class FileBrowserControllerTests: XCTestCase {
    func testNavigatingRestartsDirectoryWatcherWithoutCrashing() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let child = root.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(
            at: child,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let suiteName = "FileBrowserControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let favorite = FileBrowserLocation(
            name: root.lastPathComponent,
            url: root,
            kind: .favorite
        )
        defaults.set(
            try JSONEncoder().encode([favorite]),
            forKey: "fileBrowser.favorites"
        )
        defaults.set(root.path, forKey: "fileBrowser.lastPath")

        let controller = FileBrowserController(defaults: defaults)
        await controller.loadIfNeeded()
        await controller.navigate(to: root)
        await controller.navigate(to: child)
        await controller.goBack()

        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(controller.currentURL, root.standardizedFileURL)
    }
}
