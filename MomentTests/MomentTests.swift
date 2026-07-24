import XCTest
@testable import Moment

final class MomentTests: XCTestCase {
    func testReminderSettlementAndBoundary() {
        let start = Date(timeIntervalSince1970: 1_000)
        var repeating = ReminderRecord(
            content: "Stretch",
            intervalSeconds: 60,
            repeats: true,
            isEnabled: true,
            createdAt: start
        )
        repeating.settle(at: start.addingTimeInterval(60))
        XCTAssertTrue(repeating.isEnabled)
        XCTAssertEqual(
            repeating.nextTriggerAt,
            start.addingTimeInterval(120)
        )

        var once = ReminderRecord(
            content: "Drink water",
            intervalSeconds: 59,
            repeats: false,
            isEnabled: true,
            createdAt: start
        )
        once.settle(at: start.addingTimeInterval(59))
        XCTAssertFalse(once.isEnabled)
        XCTAssertNotNil(once.completedAt)
        XCTAssertNil(once.nextTriggerAt)
    }

    func testURLResolutionAndNormalization() {
        XCTAssertEqual(
            URLResolver.resolve("example.com/path", language: .en)?.absoluteString,
            "https://example.com/path"
        )
        XCTAssertEqual(
            URLResolver.resolve("localhost:5173", language: .zh)?.absoluteString,
            "http://localhost:5173"
        )
        XCTAssertEqual(
            URLResolver.normalized(URL(string: "https://www.Example.com/")!),
            "https://example.com"
        )
        XCTAssertTrue(
            URLResolver.resolve("片刻", language: .zh)?.absoluteString
                .hasPrefix("https://www.bing.com/search?q=") == true
        )
    }

    func testShortcutConversion() {
        let shortcut = ShortcutParser.parse("CommandOrControl+Shift+H")
        XCTAssertEqual(shortcut?.storageValue, "Command+Shift+H")
        XCTAssertEqual(shortcut?.displayValue, "⌘⇧H")
    }

    func testLegacyMigrationSkipsDamagedRows() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "state.json")
        let json = """
        {
          "version": 2,
          "reminders": [
            {
              "id": "valid",
              "content": "Take a breath",
              "intervalSeconds": 60,
              "repeat": true,
              "enabled": true,
              "createdAt": "2026-07-24T10:00:00.000Z",
              "nextTriggerAt": "2026-07-24T10:01:00.000Z",
              "completedAt": null
            },
            {
              "id": "invalid",
              "content": "",
              "intervalSeconds": 0
            }
          ],
          "bookmarks": [
            {
              "id": "bookmark",
              "title": "Example",
              "url": "https://example.com",
              "createdAt": "2026-07-24T10:00:00.000Z"
            }
          ],
          "settings": {
            "language": "zh",
            "themeMode": "dark",
            "globalShortcut": "CommandOrControl+Shift+H",
            "browserDarkMode": true
          }
        }
        """
        try Data(json.utf8).write(to: source)

        let result = try await LegacyMigrator(sourceURL: source).migrate()
        XCTAssertEqual(result?.data.reminders.map(\.id), ["valid"])
        XCTAssertEqual(result?.data.bookmarks.map(\.id), ["bookmark"])
        XCTAssertEqual(result?.preferences.appearance, .dark)
        XCTAssertEqual(result?.preferences.globalShortcut, "Command+Shift+H")
    }
}
