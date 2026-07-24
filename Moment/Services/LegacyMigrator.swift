import Foundation

struct LegacyMigrationResult: Sendable {
    var data: PersistedAppData
    var preferences: AppPreferences
}

protocol LegacyMigrating: Sendable {
    func migrate() async throws -> LegacyMigrationResult?
}

actor LegacyMigrator: LegacyMigrating {
    private let sourceURL: URL
    private let iso8601 = ISO8601DateFormatter()
    private let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(sourceURL: URL? = nil) {
        self.sourceURL = sourceURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/personal-assistant")
            .appending(path: "assistant-v2/state.json")
    }

    func migrate() throws -> LegacyMigrationResult? {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return nil
        }
        let root = try JSONSerialization.jsonObject(
            with: Data(contentsOf: sourceURL)
        )
        guard
            let object = root as? [String: Any],
            (object["version"] as? NSNumber)?.intValue == 2
        else {
            return nil
        }

        let reminders = (object["reminders"] as? [[String: Any]] ?? [])
            .compactMap(decodeReminder)
        let bookmarks = (object["bookmarks"] as? [[String: Any]] ?? [])
            .compactMap(decodeBookmark)
        let preferences = decodePreferences(
            object["settings"] as? [String: Any] ?? [:]
        )
        return LegacyMigrationResult(
            data: PersistedAppData(
                version: 1,
                reminders: reminders,
                bookmarks: bookmarks
            ),
            preferences: preferences
        )
    }

    private func decodeReminder(_ value: [String: Any]) -> ReminderRecord? {
        guard
            let id = value["id"] as? String,
            !id.isEmpty,
            let content = value["content"] as? String,
            !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            content.count <= 240,
            let seconds = (value["intervalSeconds"] as? NSNumber)?.intValue,
            (1...86_399).contains(seconds),
            let repeats = value["repeat"] as? Bool,
            let enabled = value["enabled"] as? Bool,
            let createdString = value["createdAt"] as? String,
            let createdAt = parseDate(createdString)
        else {
            return nil
        }

        return ReminderRecord(
            id: id,
            content: content,
            intervalSeconds: seconds,
            repeats: repeats,
            isEnabled: enabled,
            createdAt: createdAt,
            nextTriggerAt: date(from: value["nextTriggerAt"]),
            completedAt: date(from: value["completedAt"])
        )
    }

    private func decodeBookmark(_ value: [String: Any]) -> BookmarkRecord? {
        guard
            let id = value["id"] as? String,
            !id.isEmpty,
            let title = value["title"] as? String,
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            title.count <= 160,
            let urlString = value["url"] as? String,
            let url = URL(string: urlString),
            ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
            let createdString = value["createdAt"] as? String,
            let createdAt = parseDate(createdString)
        else {
            return nil
        }
        return BookmarkRecord(id: id, title: title, url: url, createdAt: createdAt)
    }

    private func decodePreferences(_ value: [String: Any]) -> AppPreferences {
        let legacyShortcut = value["globalShortcut"] as? String
            ?? AppPreferences.defaults.globalShortcut
        return AppPreferences(
            language: AppLanguage(rawValue: value["language"] as? String ?? "")
                ?? AppPreferences.defaults.language,
            appearance: AppearanceMode(
                rawValue: value["themeMode"] as? String ?? ""
            ) ?? AppPreferences.defaults.appearance,
            globalShortcut: legacyShortcut
                .replacingOccurrences(of: "CommandOrControl", with: "Command")
                .replacingOccurrences(of: "Meta", with: "Command")
                .replacingOccurrences(of: "Alt", with: "Option"),
            browserDarkMode: value["browserDarkMode"] as? Bool
                ?? AppPreferences.defaults.browserDarkMode
        )
    }

    private func date(from value: Any?) -> Date? {
        guard let value = value as? String else { return nil }
        return parseDate(value)
    }

    private func parseDate(_ value: String) -> Date? {
        iso8601WithFractionalSeconds.date(from: value)
            ?? iso8601.date(from: value)
    }
}
