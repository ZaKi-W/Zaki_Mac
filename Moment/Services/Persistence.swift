import Foundation

protocol ReminderRepository: Sendable {
    func loadData() async throws -> PersistedAppData?
    func saveData(_ data: PersistedAppData) async throws
}

protocol BookmarkRepository: Sendable {
    func loadData() async throws -> PersistedAppData?
    func saveData(_ data: PersistedAppData) async throws
}

actor JSONAppDataStore: ReminderRepository, BookmarkRepository {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: URL? = nil) {
        let root = baseURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appending(path: "Moment", directoryHint: .isDirectory)
        fileURL = root.appending(path: "app-state.json", directoryHint: .notDirectory)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadData() throws -> PersistedAppData? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return try decoder.decode(PersistedAppData.self, from: Data(contentsOf: fileURL))
    }

    func saveData(_ data: PersistedAppData) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try encoder.encode(data).write(to: fileURL, options: .atomic)
    }
}

@MainActor
final class PreferencesStore {
    private enum Key {
        static let language = "preferences.language"
        static let appearance = "preferences.appearance"
        static let globalShortcut = "preferences.globalShortcut"
        static let browserDarkMode = "preferences.browserDarkMode"
        static let legacyMigrationCompleted = "migration.legacy-v2.completed"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppPreferences {
        AppPreferences(
            language: AppLanguage(
                rawValue: defaults.string(forKey: Key.language) ?? ""
            ) ?? AppPreferences.defaults.language,
            appearance: AppearanceMode(
                rawValue: defaults.string(forKey: Key.appearance) ?? ""
            ) ?? AppPreferences.defaults.appearance,
            globalShortcut: defaults.string(forKey: Key.globalShortcut)
                ?? AppPreferences.defaults.globalShortcut,
            browserDarkMode: defaults.object(forKey: Key.browserDarkMode) == nil
                ? AppPreferences.defaults.browserDarkMode
                : defaults.bool(forKey: Key.browserDarkMode)
        )
    }

    func save(_ preferences: AppPreferences) {
        defaults.set(preferences.language.rawValue, forKey: Key.language)
        defaults.set(preferences.appearance.rawValue, forKey: Key.appearance)
        defaults.set(preferences.globalShortcut, forKey: Key.globalShortcut)
        defaults.set(preferences.browserDarkMode, forKey: Key.browserDarkMode)
    }

    var legacyMigrationCompleted: Bool {
        get { defaults.bool(forKey: Key.legacyMigrationCompleted) }
        set { defaults.set(newValue, forKey: Key.legacyMigrationCompleted) }
    }
}
