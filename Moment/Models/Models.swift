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

/// A calendar day stored as civil date components instead of an absolute `Date`.
/// This keeps a scheduled day stable when the system time zone changes.
struct LocalDay: Codable, Hashable, Comparable, Sendable {
    var year: Int
    var month: Int
    var day: Int

    init(year: Int, month: Int, day: Int) {
        let normalizedMonth = min(max(month, 1), 12)
        self.year = year
        self.month = normalizedMonth
        self.day = min(
            max(day, 1),
            Self.daysInMonth(year: year, month: normalizedMonth)
        )
    }

    init(date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: date
        )
        self.init(
            year: components.year ?? 1,
            month: components.month ?? 1,
            day: components.day ?? 1
        )
    }

    static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    func date(
        at time: LocalTime? = nil,
        calendar: Calendar = .current
    ) -> Date? {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: time?.hour ?? 0,
                minute: time?.minute ?? 0
            )
        )
    }

    func addingDays(
        _ value: Int,
        calendar: Calendar = .current
    ) -> LocalDay? {
        guard let date = date(calendar: calendar),
              let result = calendar.date(byAdding: .day, value: value, to: date) else {
            return nil
        }
        return LocalDay(date: result, calendar: calendar)
    }

    func addingMonths(_ value: Int) -> LocalDay {
        let zeroBasedMonth = year * 12 + month - 1 + value
        let targetYear = zeroBasedMonth >= 0
            ? zeroBasedMonth / 12
            : (zeroBasedMonth - 11) / 12
        let targetMonth = zeroBasedMonth - targetYear * 12 + 1
        return LocalDay(year: targetYear, month: targetMonth, day: day)
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month)
        guard let date = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            return 31
        }
        return range.count
    }

    private enum CodingKeys: String, CodingKey {
        case year
        case month
        case day
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let year = try container.decode(Int.self, forKey: .year)
        let month = try container.decode(Int.self, forKey: .month)
        let day = try container.decode(Int.self, forKey: .day)
        guard (1...12).contains(month),
              (1...Self.daysInMonth(year: year, month: month)).contains(day) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid local calendar day"
                )
            )
        }
        self.year = year
        self.month = month
        self.day = day
    }
}

/// A wall-clock time stored without a date or time zone.
struct LocalTime: Codable, Hashable, Comparable, Sendable {
    var hour: Int
    var minute: Int

    static let midnight = LocalTime(hour: 0, minute: 0)
    static let nineAM = LocalTime(hour: 9, minute: 0)

    init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    init(date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        self.init(
            hour: components.hour ?? 0,
            minute: components.minute ?? 0
        )
    }

    static func < (lhs: LocalTime, rhs: LocalTime) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }

    private enum CodingKeys: String, CodingKey {
        case hour
        case minute
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hour = try container.decode(Int.self, forKey: .hour)
        let minute = try container.decode(Int.self, forKey: .minute)
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid local wall-clock time"
                )
            )
        }
        self.hour = hour
        self.minute = minute
    }
}

enum TodoRecurrence: String, Codable, CaseIterable, Sendable {
    case none
    case monthly
}

/// Stable identity for one occurrence. A monthly occurrence is keyed by the
/// series ID and its source year/month, even when an override moves its day.
struct TodoOccurrenceID: RawRepresentable, Codable, Hashable, Sendable {
    var todoID: String
    var year: Int?
    var month: Int?

    init(todoID: String, year: Int? = nil, month: Int? = nil) {
        self.todoID = todoID
        if let year, let month, (1...12).contains(month) {
            self.year = year
            self.month = month
        } else {
            self.year = nil
            self.month = nil
        }
    }

    static func once(todoID: String) -> TodoOccurrenceID {
        TodoOccurrenceID(todoID: todoID)
    }

    static func monthly(
        todoID: String,
        year: Int,
        month: Int
    ) -> TodoOccurrenceID {
        TodoOccurrenceID(todoID: todoID, year: year, month: month)
    }

    var isMonthly: Bool {
        year != nil && month != nil
    }

    var rawValue: String {
        guard let year, let month else { return "\(todoID)|once" }
        return String(format: "%@|%04d-%02d", todoID, year, month)
    }

    init?(rawValue: String) {
        guard let separator = rawValue.lastIndex(of: "|") else { return nil }
        let todoID = String(rawValue[..<separator])
        let period = String(rawValue[rawValue.index(after: separator)...])
        guard !todoID.isEmpty else { return nil }
        if period == "once" {
            self.init(todoID: todoID)
            return
        }
        let parts = period.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              (1...12).contains(month) else {
            return nil
        }
        self.init(todoID: todoID, year: year, month: month)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let value = TodoOccurrenceID(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid todo occurrence ID"
            )
        }
        self = value
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum TodoOccurrenceState: String, Codable, Sendable {
    case active
    case completed
    case skipped
}

struct TodoOccurrenceStatus: Codable, Identifiable, Equatable, Sendable {
    var occurrenceID: TodoOccurrenceID
    var state: TodoOccurrenceState
    var changedAt: Date

    var id: TodoOccurrenceID { occurrenceID }

    init(
        occurrenceID: TodoOccurrenceID,
        state: TodoOccurrenceState,
        changedAt: Date = .now
    ) {
        self.occurrenceID = occurrenceID
        self.state = state
        self.changedAt = changedAt
    }
}

/// A complete effective-value snapshot for one edited occurrence. Using a full
/// snapshot lets optional values such as `startTime` be explicitly cleared.
struct TodoOccurrenceOverride: Codable, Identifiable, Equatable, Sendable {
    var occurrenceID: TodoOccurrenceID
    var title: String
    var scheduledDay: LocalDay
    var startTime: LocalTime?
    var notificationEnabled: Bool
    var notificationTime: LocalTime?
    var completionFollowUpEnabled: Bool

    var id: TodoOccurrenceID { occurrenceID }

    init(
        occurrenceID: TodoOccurrenceID,
        title: String,
        scheduledDay: LocalDay,
        startTime: LocalTime? = nil,
        notificationEnabled: Bool = false,
        notificationTime: LocalTime? = nil,
        completionFollowUpEnabled: Bool = false
    ) {
        self.occurrenceID = occurrenceID
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.scheduledDay = scheduledDay
        self.startTime = startTime
        self.notificationEnabled = notificationEnabled
        self.notificationTime = notificationEnabled
            ? (notificationTime ?? startTime ?? .nineAM)
            : nil
        self.completionFollowUpEnabled = completionFollowUpEnabled
    }
}

struct TodoOccurrence: Identifiable, Equatable, Sendable {
    var id: TodoOccurrenceID
    var todoID: String
    var title: String
    var baseScheduledDay: LocalDay?
    var scheduledDay: LocalDay?
    var startTime: LocalTime?
    var recurrence: TodoRecurrence
    var notificationEnabled: Bool
    var notificationTime: LocalTime?
    var completionFollowUpEnabled: Bool
    var state: TodoOccurrenceState
    var stateChangedAt: Date?

    var isRecurring: Bool { recurrence != .none }
    var isCompleted: Bool { state == .completed }
    var isSkipped: Bool { state == .skipped }
}

struct TodoRecord: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var createdAt: Date
    var completedAt: Date?
    var scheduledDay: LocalDay?
    var startTime: LocalTime?
    var recurrence: TodoRecurrence
    var notificationEnabled: Bool
    var notificationTime: LocalTime?
    var completionFollowUpEnabled: Bool
    var seriesEndDay: LocalDay?
    var occurrenceStatuses: [TodoOccurrenceStatus]
    var occurrenceOverrides: [TodoOccurrenceOverride]

    var isCompleted: Bool {
        completedAt != nil
    }

    var isScheduled: Bool {
        scheduledDay != nil
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        createdAt: Date = .now,
        completedAt: Date? = nil,
        scheduledDay: LocalDay? = nil,
        startTime: LocalTime? = nil,
        recurrence: TodoRecurrence = .none,
        notificationEnabled: Bool = false,
        notificationTime: LocalTime? = nil,
        completionFollowUpEnabled: Bool? = nil,
        seriesEndDay: LocalDay? = nil,
        occurrenceStatuses: [TodoOccurrenceStatus] = [],
        occurrenceOverrides: [TodoOccurrenceOverride] = []
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.scheduledDay = scheduledDay
        self.startTime = scheduledDay == nil ? nil : startTime
        self.recurrence = scheduledDay == nil ? .none : recurrence
        self.notificationEnabled = scheduledDay == nil
            ? false
            : notificationEnabled
        self.notificationTime = self.notificationEnabled
            ? (notificationTime ?? startTime ?? .nineAM)
            : nil
        self.completionFollowUpEnabled = scheduledDay == nil
            ? false
            : (completionFollowUpEnabled ?? (recurrence == .monthly))
        self.seriesEndDay = self.recurrence == .monthly ? seriesEndDay : nil
        self.occurrenceStatuses = occurrenceStatuses
        self.occurrenceOverrides = occurrenceOverrides
    }

    mutating func rename(_ title: String) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func setCompleted(_ completed: Bool, at date: Date = .now) {
        completedAt = completed ? date : nil
    }

    func occurrenceID(year: Int? = nil, month: Int? = nil) -> TodoOccurrenceID {
        if recurrence == .monthly, let year, let month {
            return .monthly(todoID: id, year: year, month: month)
        }
        return .once(todoID: id)
    }

    func state(for occurrenceID: TodoOccurrenceID) -> TodoOccurrenceState {
        guard occurrenceID.todoID == id else { return .active }
        if let status = occurrenceStatuses.last(where: {
            $0.occurrenceID == occurrenceID
        }) {
            return status.state
        }
        if recurrence == .none,
           occurrenceID == .once(todoID: id),
           completedAt != nil {
            return .completed
        }
        return .active
    }

    func occurrence(
        for occurrenceID: TodoOccurrenceID,
        calendar: Calendar = .current
    ) -> TodoOccurrence? {
        guard occurrenceID.todoID == id else { return nil }

        let baseDay: LocalDay?
        switch recurrence {
        case .none:
            guard !occurrenceID.isMonthly else { return nil }
            baseDay = scheduledDay
        case .monthly:
            guard let scheduledDay,
                  let year = occurrenceID.year,
                  let month = occurrenceID.month,
                  monthIndex(year: year, month: month) >= monthIndex(
                    year: scheduledDay.year,
                    month: scheduledDay.month
                  ) else {
                return nil
            }
            baseDay = LocalDay(
                year: year,
                month: month,
                day: scheduledDay.day
            )
        }

        if let seriesEndDay, let baseDay, baseDay > seriesEndDay { return nil }
        let override = occurrenceOverrides.last {
            $0.occurrenceID == occurrenceID
        }
        let status = occurrenceStatuses.last {
            $0.occurrenceID == occurrenceID
        }
        let resolvedState: TodoOccurrenceState
        let stateChangedAt: Date?
        if let status {
            resolvedState = status.state
            stateChangedAt = status.changedAt
        } else if recurrence == .none, let completedAt {
            resolvedState = .completed
            stateChangedAt = completedAt
        } else {
            resolvedState = .active
            stateChangedAt = nil
        }

        return TodoOccurrence(
            id: occurrenceID,
            todoID: id,
            title: override?.title ?? title,
            baseScheduledDay: baseDay,
            scheduledDay: override?.scheduledDay ?? baseDay,
            startTime: override == nil ? startTime : override?.startTime,
            recurrence: recurrence,
            notificationEnabled: override?.notificationEnabled
                ?? notificationEnabled,
            notificationTime: override == nil
                ? notificationTime
                : override?.notificationTime,
            completionFollowUpEnabled: override?.completionFollowUpEnabled
                ?? completionFollowUpEnabled,
            state: resolvedState,
            stateChangedAt: stateChangedAt
        )
    }

    func occurrences(
        on day: LocalDay,
        calendar: Calendar = .current
    ) -> [TodoOccurrence] {
        occurrences(from: day, through: day, calendar: calendar)
    }

    func occurrence(
        on day: LocalDay,
        calendar: Calendar = .current
    ) -> TodoOccurrence? {
        occurrences(on: day, calendar: calendar).first
    }

    func occurrences(
        from startDay: LocalDay,
        through endDay: LocalDay,
        calendar: Calendar = .current
    ) -> [TodoOccurrence] {
        guard startDay <= endDay else { return [] }
        var candidateIDs = Set<TodoOccurrenceID>()

        switch recurrence {
        case .none:
            candidateIDs.insert(.once(todoID: id))
        case .monthly:
            guard let scheduledDay else { return [] }
            let firstIndex = monthIndex(
                year: scheduledDay.year,
                month: scheduledDay.month
            )
            let lastIndex = monthIndex(year: endDay.year, month: endDay.month)
            if firstIndex <= lastIndex {
                for index in firstIndex...lastIndex {
                    let components = yearAndMonth(for: index)
                    candidateIDs.insert(
                        .monthly(
                            todoID: id,
                            year: components.year,
                            month: components.month
                        )
                    )
                }
            }
            candidateIDs.formUnion(occurrenceOverrides.map(\.occurrenceID))
        }

        return candidateIDs.compactMap {
            occurrence(for: $0, calendar: calendar)
        }
        .filter {
            guard let day = $0.scheduledDay else { return false }
            return day >= startDay && day <= endDay
        }
        .sorted {
            if $0.scheduledDay != $1.scheduledDay {
                return ($0.scheduledDay ?? startDay)
                    < ($1.scheduledDay ?? startDay)
            }
            switch ($0.startTime, $1.startTime) {
            case let (.some(lhs), .some(rhs)) where lhs != rhs:
                return lhs < rhs
            case (.none, .some):
                return true
            case (.some, .none):
                return false
            default:
                return $0.id.rawValue < $1.id.rawValue
            }
        }
    }

    mutating func setOccurrenceCompleted(
        _ occurrenceID: TodoOccurrenceID,
        completed: Bool,
        at date: Date = .now
    ) {
        guard occurrenceID.todoID == id else { return }
        if recurrence == .none, occurrenceID == .once(todoID: id) {
            completedAt = completed ? date : nil
            removeOccurrenceStatus(for: occurrenceID)
            return
        }
        removeOccurrenceStatus(for: occurrenceID)
        if completed {
            occurrenceStatuses.append(
                TodoOccurrenceStatus(
                    occurrenceID: occurrenceID,
                    state: .completed,
                    changedAt: date
                )
            )
        }
    }

    mutating func setOccurrenceCompleted(
        _ completed: Bool,
        occurrenceID: TodoOccurrenceID,
        at date: Date = .now
    ) {
        setOccurrenceCompleted(occurrenceID, completed: completed, at: date)
    }

    mutating func markOccurrenceSkipped(
        _ occurrenceID: TodoOccurrenceID,
        at date: Date = .now
    ) {
        guard occurrenceID.todoID == id else { return }
        if recurrence == .none { completedAt = nil }
        removeOccurrenceStatus(for: occurrenceID)
        occurrenceStatuses.append(
            TodoOccurrenceStatus(
                occurrenceID: occurrenceID,
                state: .skipped,
                changedAt: date
            )
        )
    }

    mutating func clearOccurrenceState(for occurrenceID: TodoOccurrenceID) {
        if recurrence == .none { completedAt = nil }
        removeOccurrenceStatus(for: occurrenceID)
    }

    mutating func setOccurrenceOverride(_ override: TodoOccurrenceOverride) {
        guard override.occurrenceID.todoID == id else { return }
        occurrenceOverrides.removeAll {
            $0.occurrenceID == override.occurrenceID
        }
        occurrenceOverrides.append(override)
    }

    mutating func removeOccurrenceOverride(for occurrenceID: TodoOccurrenceID) {
        occurrenceOverrides.removeAll { $0.occurrenceID == occurrenceID }
    }

    @discardableResult
    mutating func markPastMonthlyOccurrencesSkipped(
        before day: LocalDay,
        at date: Date = .now
    ) -> [TodoOccurrenceID] {
        guard recurrence == .monthly, let scheduledDay else { return [] }
        var skipped: [TodoOccurrenceID] = []
        let dueOccurrences = occurrences(from: scheduledDay, through: day)
        guard dueOccurrences.count > 1 else { return [] }
        for occurrence in dueOccurrences.dropLast()
        where occurrence.state == .active {
            markOccurrenceSkipped(occurrence.id, at: date)
            skipped.append(occurrence.id)
        }
        return skipped
    }

    private mutating func removeOccurrenceStatus(
        for occurrenceID: TodoOccurrenceID
    ) {
        occurrenceStatuses.removeAll { $0.occurrenceID == occurrenceID }
    }

    private func monthIndex(year: Int, month: Int) -> Int {
        year * 12 + month - 1
    }

    private func yearAndMonth(for index: Int) -> (year: Int, month: Int) {
        let year = index >= 0 ? index / 12 : (index - 11) / 12
        return (year, index - year * 12 + 1)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt
        case completedAt
        case scheduledDay
        case startTime
        case recurrence
        case notificationEnabled
        case notificationTime
        case completionFollowUpEnabled
        case seriesEndDay
        case occurrenceStatuses
        case occurrenceOverrides
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        scheduledDay = try container.decodeIfPresent(
            LocalDay.self,
            forKey: .scheduledDay
        )
        startTime = try container.decodeIfPresent(LocalTime.self, forKey: .startTime)
        recurrence = try container.decodeIfPresent(
            TodoRecurrence.self,
            forKey: .recurrence
        ) ?? .none
        notificationEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .notificationEnabled
        ) ?? false
        notificationTime = try container.decodeIfPresent(
            LocalTime.self,
            forKey: .notificationTime
        )
        let decodedCompletionFollowUp = try container.decodeIfPresent(
            Bool.self,
            forKey: .completionFollowUpEnabled
        )
        completionFollowUpEnabled = decodedCompletionFollowUp
            ?? (recurrence == .monthly)
        seriesEndDay = try container.decodeIfPresent(
            LocalDay.self,
            forKey: .seriesEndDay
        )
        occurrenceStatuses = try container.decodeIfPresent(
            [TodoOccurrenceStatus].self,
            forKey: .occurrenceStatuses
        ) ?? []
        occurrenceOverrides = try container.decodeIfPresent(
            [TodoOccurrenceOverride].self,
            forKey: .occurrenceOverrides
        ) ?? []

        if scheduledDay == nil {
            startTime = nil
            recurrence = .none
            notificationEnabled = false
            notificationTime = nil
            completionFollowUpEnabled = false
            seriesEndDay = nil
        } else {
            if notificationEnabled, notificationTime == nil {
                notificationTime = startTime ?? .nineAM
            } else if !notificationEnabled {
                notificationTime = nil
            }
            if recurrence == .none {
                seriesEndDay = nil
            }
        }
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

    static let currentVersion = 5

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
