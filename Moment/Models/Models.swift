import Foundation

enum Workspace: String, CaseIterable, Identifiable, Sendable {
    case dashboard
    case inventory
    case assets
    case expenses
    case todos
    case reminders
    case runningProjects
    case files
    case aiHot
    case browser

    var id: Self { self }
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case zh
    case en

    var id: Self { self }
    var localeIdentifier: String { self == .zh ? "zh-Hans" : "en" }
}

enum AppearanceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: Self { self }
}

struct AppPreferences: Codable, Equatable, Sendable {
    var language: AppLanguage
    var appearance: AppearanceMode
    var globalShortcut: String
    var browserDarkMode: Bool

    static let defaults = AppPreferences(
        language: .zh,
        appearance: .system,
        globalShortcut: "Command+Shift+H",
        browserDarkMode: false
    )
}

struct ReminderRecord: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var content: String
    var intervalSeconds: Int
    var repeats: Bool
    var isEnabled: Bool
    var createdAt: Date
    var nextTriggerAt: Date?
    var completedAt: Date?

    init(
        id: String = UUID().uuidString,
        content: String,
        intervalSeconds: Int,
        repeats: Bool,
        isEnabled: Bool,
        createdAt: Date = .now,
        nextTriggerAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        self.intervalSeconds = min(max(intervalSeconds, 1), 86_399)
        self.repeats = repeats
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.nextTriggerAt = isEnabled
            ? (nextTriggerAt ?? createdAt.addingTimeInterval(TimeInterval(intervalSeconds)))
            : nil
        self.completedAt = completedAt
    }

    mutating func apply(_ draft: ReminderDraft, now: Date = .now) {
        content = draft.content.trimmingCharacters(in: .whitespacesAndNewlines)
        intervalSeconds = min(max(draft.intervalSeconds, 1), 86_399)
        repeats = draft.repeats
        isEnabled = draft.isEnabled
        completedAt = nil
        nextTriggerAt = draft.isEnabled
            ? now.addingTimeInterval(TimeInterval(intervalSeconds))
            : nil
    }

    mutating func setEnabled(_ enabled: Bool, now: Date = .now) {
        isEnabled = enabled
        completedAt = nil
        nextTriggerAt = enabled
            ? now.addingTimeInterval(TimeInterval(intervalSeconds))
            : nil
    }

    mutating func settle(at date: Date = .now) {
        if repeats {
            completedAt = nil
            nextTriggerAt = date.addingTimeInterval(TimeInterval(intervalSeconds))
        } else {
            isEnabled = false
            completedAt = date
            nextTriggerAt = nil
        }
    }
}

struct ReminderDraft: Identifiable, Equatable, Sendable {
    let id = UUID()
    var editingID: String?
    var content: String
    var hours: Int
    var minutes: Int
    var seconds: Int
    var repeats: Bool
    var isEnabled: Bool

    var intervalSeconds: Int {
        hours * 3_600 + minutes * 60 + seconds
    }

    var isValid: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && intervalSeconds > 0
            && intervalSeconds <= 86_399
    }

    static var fresh: ReminderDraft {
        ReminderDraft(
            editingID: nil,
            content: "",
            hours: 0,
            minutes: 0,
            seconds: 30,
            repeats: true,
            isEnabled: true
        )
    }

    init(reminder: ReminderRecord) {
        editingID = reminder.id
        content = reminder.content
        hours = reminder.intervalSeconds / 3_600
        minutes = (reminder.intervalSeconds % 3_600) / 60
        seconds = reminder.intervalSeconds % 60
        repeats = reminder.repeats
        isEnabled = reminder.isEnabled
    }

    init(
        editingID: String?,
        content: String,
        hours: Int,
        minutes: Int,
        seconds: Int,
        repeats: Bool,
        isEnabled: Bool
    ) {
        self.editingID = editingID
        self.content = content
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
        self.repeats = repeats
        self.isEnabled = isEnabled
    }
}

struct TodoRecord: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var createdAt: Date
    var completedAt: Date?

    var isCompleted: Bool {
        completedAt != nil
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        createdAt: Date = .now,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    mutating func rename(_ title: String) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func setCompleted(_ completed: Bool, at date: Date = .now) {
        completedAt = completed ? date : nil
    }
}

struct BookmarkRecord: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var url: URL
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        url: URL,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.createdAt = createdAt
    }
}

struct BrowserTabState: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var url: URL?
    var title: String
    var isLoading: Bool
    var canGoBack: Bool
    var canGoForward: Bool
}

struct PersistedAppData: Codable, Equatable, Sendable {
    var version: Int
    var reminders: [ReminderRecord]
    var bookmarks: [BookmarkRecord]
    var todos: [TodoRecord]
    var life: LifeData

    static let currentVersion = 4

    static let empty = PersistedAppData(
        version: currentVersion,
        reminders: [],
        bookmarks: [],
        todos: [],
        life: .empty
    )

    init(
        version: Int = PersistedAppData.currentVersion,
        reminders: [ReminderRecord],
        bookmarks: [BookmarkRecord],
        todos: [TodoRecord] = [],
        life: LifeData = .empty
    ) {
        self.version = version
        self.reminders = reminders
        self.bookmarks = bookmarks
        self.todos = todos
        self.life = life
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case reminders
        case bookmarks
        case todos
        case life
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        reminders = try container.decodeIfPresent(
            [ReminderRecord].self,
            forKey: .reminders
        ) ?? []
        bookmarks = try container.decodeIfPresent(
            [BookmarkRecord].self,
            forKey: .bookmarks
        ) ?? []
        todos = try container.decodeIfPresent(
            [TodoRecord].self,
            forKey: .todos
        ) ?? []
        life = try container.decodeIfPresent(LifeData.self, forKey: .life) ?? .empty
    }
}

enum URLResolver {
    static func resolve(_ input: String, language: AppLanguage) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if let url = URL(string: value),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return url
        }

        if value.range(
            of: #"^[\w-]+(\.[\w-]+)+(:\d+)?(/.*)?$"#,
            options: .regularExpression
        ) != nil {
            return URL(string: "https://\(value)")
        }

        if value.range(
            of: #"^localhost(:\d+)?(/.*)?$"#,
            options: .regularExpression
        ) != nil {
            return URL(string: "http://\(value)")
        }

        let engine = language == .zh
            ? "https://www.bing.com/search?q="
            : "https://www.google.com/search?q="
        return URL(string: engine + value.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        )!)
    }

    static func normalized(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.host = components.host?.lowercased().replacingOccurrences(
            of: #"^www\."#,
            with: "",
            options: .regularExpression
        )
        if components.path == "/" {
            components.path = ""
        }
        return components.string ?? url.absoluteString
    }
}
