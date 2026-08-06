import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum TodoViewMode: String, CaseIterable, Identifiable, Sendable {
    case todos
    case calendar

    var id: Self { self }
}

enum TodoEditScope: String, CaseIterable, Identifiable, Sendable {
    case onlyThis
    case thisAndFuture

    var id: Self { self }
}

struct TodoEditorDraft: Identifiable, Equatable, Sendable {
    let id = UUID()
    var editingOccurrenceID: TodoOccurrenceID?
    var title: String
    var scheduledDay: LocalDay?
    var startTime: LocalTime?
    var recurrence: TodoRecurrence
    var notificationEnabled: Bool
    var notificationTime: LocalTime?
    var completionFollowUpEnabled: Bool
    var editScope: TodoEditScope

    var isEditing: Bool { editingOccurrenceID != nil }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (scheduledDay != nil || recurrence == .none)
    }

    init(
        editingOccurrenceID: TodoOccurrenceID? = nil,
        title: String = "",
        scheduledDay: LocalDay? = nil,
        startTime: LocalTime? = nil,
        recurrence: TodoRecurrence = .none,
        notificationEnabled: Bool = false,
        notificationTime: LocalTime? = nil,
        completionFollowUpEnabled: Bool = false,
        editScope: TodoEditScope = .onlyThis
    ) {
        self.editingOccurrenceID = editingOccurrenceID
        self.title = title
        self.scheduledDay = scheduledDay
        self.startTime = startTime
        self.recurrence = scheduledDay == nil ? .none : recurrence
        self.notificationEnabled = scheduledDay != nil && notificationEnabled
        self.notificationTime = scheduledDay != nil && notificationEnabled
            ? (notificationTime ?? startTime ?? .nineAM)
            : nil
        self.completionFollowUpEnabled = scheduledDay != nil
            && completionFollowUpEnabled
        self.editScope = editScope
    }

    init(occurrence: TodoOccurrence) {
        editingOccurrenceID = occurrence.id
        title = occurrence.title
        scheduledDay = occurrence.scheduledDay
        startTime = occurrence.startTime
        recurrence = occurrence.recurrence
        notificationEnabled = occurrence.notificationEnabled
        notificationTime = occurrence.notificationTime
        completionFollowUpEnabled = occurrence.completionFollowUpEnabled
        editScope = .onlyThis
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var workspace: Workspace = .dashboard
    @Published private(set) var reminders: [ReminderRecord] = []
    @Published private(set) var bookmarks: [BookmarkRecord] = []
    @Published private(set) var todos: [TodoRecord] = []
    @Published private(set) var life: LifeData = .empty
    @Published private(set) var preferences: AppPreferences
    @Published var reminderDraft: ReminderDraft?
    @Published var pendingDeletion: ReminderRecord?
    @Published var todoViewMode: TodoViewMode = .todos
    @Published var todoDraft: TodoEditorDraft?
    @Published var pendingTodoDeletion: TodoOccurrence?
    @Published private(set) var currentDay = LocalDay(date: .now)
    @Published var highlightedTodoOccurrenceID: TodoOccurrenceID?
    @Published var showingInventoryReview = false
    @Published var highlightedExpenseID: String?
    @Published var todoEntryFocusRequest = 0
    @Published var statusMessage: String?
    @Published private(set) var notificationState: NotificationAuthorizationState = .unknown

    let browser = BrowserController()
    let aiHot = AIHotController()
    let runningProjects = RunningProjectsController()
    let files = FileBrowserController()

    private let dataStore: JSONAppDataStore
    private let migrator: LegacyMigrator
    private let preferencesStore: PreferencesStore
    private let scheduler: ReminderScheduler
    private let hotKeyManager: GlobalHotKeyManager
    private var started = false
    private var dataLoaded = false
    private var pendingNotificationSelections: [[AnyHashable: Any]] = []

    private init(
        dataStore: JSONAppDataStore = JSONAppDataStore(),
        migrator: LegacyMigrator = LegacyMigrator(),
        preferencesStore: PreferencesStore = PreferencesStore(),
        scheduler: ReminderScheduler = ReminderScheduler(),
        hotKeyManager: GlobalHotKeyManager = GlobalHotKeyManager()
    ) {
        self.dataStore = dataStore
        self.migrator = migrator
        self.preferencesStore = preferencesStore
        self.scheduler = scheduler
        self.hotKeyManager = hotKeyManager
        preferences = preferencesStore.load()
        applyAppearance()
    }

    var locale: Locale {
        Locale(identifier: preferences.language.localeIdentifier)
    }

    var preferredColorScheme: ColorScheme? {
        switch preferences.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    func text(_ key: String) -> String {
        L10n.text(key, preferences.language)
    }

    func start() {
        guard !started else { return }
        started = true
        registerGlobalShortcut(preferences.globalShortcut)

        Task {
            do {
                var data = try await dataStore.loadData()
                if data == nil, !preferencesStore.legacyMigrationCompleted {
                    if let migrated = try await migrator.migrate() {
                        data = migrated.data
                        preferences = migrated.preferences
                        preferencesStore.save(preferences)
                        preferencesStore.legacyMigrationCompleted = true
                        try await dataStore.saveData(migrated.data)
                        statusMessage = text("status.migrated")
                    } else {
                        preferencesStore.legacyMigrationCompleted = true
                    }
                }
                reminders = data?.reminders ?? []
                bookmarks = data?.bookmarks ?? []
                todos = data?.todos ?? []
                life = data?.life ?? .empty
                currentDay = LocalDay(date: .now)
                let normalizedTodos = normalizeRecurringTodoStates()
                dataLoaded = true
                applyAppearance()
                browser.setDarkMode(preferences.browserDarkMode)
                registerGlobalShortcut(preferences.globalShortcut)
                if normalizedTodos {
                    persistData()
                }
                let queuedSelections = pendingNotificationSelections
                pendingNotificationSelections.removeAll()
                for selection in queuedSelections {
                    processNotificationSelection(selection)
                }
                await refreshNotificationState()
                await synchronizeNotifications()
            } catch {
                reminders = []
                bookmarks = []
                todos = []
                life = .empty
                dataLoaded = true
                let queuedSelections = pendingNotificationSelections
                pendingNotificationSelections.removeAll()
                for selection in queuedSelections {
                    processNotificationSelection(selection)
                }
                statusMessage = error.localizedDescription
            }
        }
    }

    func openNewReminder() {
        workspace = .reminders
        reminderDraft = .fresh
    }

    func edit(_ reminder: ReminderRecord) {
        workspace = .reminders
        reminderDraft = ReminderDraft(reminder: reminder)
    }

    func saveReminder(_ draft: ReminderDraft) async {
        guard draft.isValid else { return }
        if draft.isEnabled {
            let allowed = await scheduler.requestAuthorization()
            await refreshNotificationState()
            if !allowed {
                statusMessage = text("status.permissionDenied")
            }
        }

        if let editingID = draft.editingID,
           let index = reminders.firstIndex(where: { $0.id == editingID }) {
            reminders[index].apply(draft)
        } else {
            reminders.append(
                ReminderRecord(
                    content: draft.content,
                    intervalSeconds: draft.intervalSeconds,
                    repeats: draft.repeats,
                    isEnabled: draft.isEnabled
                )
            )
        }
        reminderDraft = nil
        persistData()
        await synchronizeNotifications()
    }

    func toggle(_ reminder: ReminderRecord) {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else {
            return
        }
        reminders[index].setEnabled(!reminder.isEnabled)
        let enabled = reminders[index].isEnabled
        persistData()
        Task {
            if enabled {
                _ = await scheduler.requestAuthorization()
                await refreshNotificationState()
            }
            await synchronizeNotifications()
        }
    }

    func requestDelete(_ reminder: ReminderRecord) {
        pendingDeletion = reminder
    }

    func confirmDelete() {
        guard let pendingDeletion else { return }
        reminders.removeAll { $0.id == pendingDeletion.id }
        self.pendingDeletion = nil
        persistData()
        Task { await synchronizeNotifications() }
    }

    func openNewTodo() {
        workspace = .todos
        todoViewMode = .todos
        todoEntryFocusRequest += 1
    }

    func openNewTodo(for day: LocalDay?) {
        workspace = .todos
        if day != nil {
            todoViewMode = .calendar
        }
        todoDraft = TodoEditorDraft(scheduledDay: day)
    }

    func edit(_ occurrence: TodoOccurrence) {
        workspace = .todos
        todoDraft = TodoEditorDraft(occurrence: occurrence)
    }

    var todayOccurrences: [TodoOccurrence] {
        let today = currentDay
        let occurrences = todos.flatMap { todo -> [TodoOccurrence] in
            guard todo.scheduledDay != nil else { return [] }
            switch todo.recurrence {
            case .none:
                guard let occurrence = todo.occurrence(
                    for: .once(todoID: todo.id)
                ), let day = occurrence.scheduledDay else {
                    return []
                }
                if occurrence.state == .active, day <= today {
                    return [occurrence]
                }
                return day == today && occurrence.state == .completed
                    ? [occurrence]
                    : []
            case .monthly:
                guard let anchor = todo.scheduledDay else { return [] }
                let due = todo.occurrences(from: anchor, through: today)
                guard let latest = due.last else { return [] }
                if latest.state == .active {
                    return [latest]
                }
                return latest.scheduledDay == today
                    && latest.state == .completed
                    ? [latest]
                    : []
            }
        }
        return occurrences.sorted(by: todoOccurrenceSort)
    }

    var allTodoOccurrences: [TodoOccurrence] {
        let calendar = Calendar.current
        let futureDate = calendar.date(
            byAdding: .month,
            value: 12,
            to: currentDay.date(calendar: calendar) ?? .now
        ) ?? .now
        let futureDay = LocalDay(date: futureDate, calendar: calendar)

        return todos.flatMap { todo -> [TodoOccurrence] in
            switch todo.recurrence {
            case .none:
                return todo.occurrence(for: .once(todoID: todo.id)).map { [$0] }
                    ?? []
            case .monthly:
                guard let anchor = todo.scheduledDay else { return [] }
                return todo.occurrences(
                    from: anchor,
                    through: max(futureDay, currentDay)
                )
            }
        }
        .sorted(by: todoOccurrenceSort)
    }

    func occurrences(on day: LocalDay) -> [TodoOccurrence] {
        todos.flatMap { $0.occurrences(on: day) }
            .sorted(by: todoOccurrenceSort)
    }

    @discardableResult
    func addTodo(title: String) -> Bool {
        quickAddTodo(title: title, scheduledDay: nil)
    }

    @discardableResult
    func quickAddTodo(title: String, scheduledDay: LocalDay?) -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return false }
        todos.append(
            TodoRecord(title: trimmedTitle, scheduledDay: scheduledDay)
        )
        persistData()
        return true
    }

    func saveTodo(_ draft: TodoEditorDraft) async {
        guard draft.isValid else { return }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.notificationEnabled {
            let allowed = await scheduler.requestAuthorization()
            await refreshNotificationState()
            if !allowed {
                statusMessage = text("status.permissionDenied")
            }
        }

        if let occurrenceID = draft.editingOccurrenceID,
           let index = todos.firstIndex(where: { $0.id == occurrenceID.todoID }),
           let occurrence = todos[index].occurrence(for: occurrenceID) {
            if occurrence.isRecurring {
                switch draft.editScope {
                case .onlyThis:
                    guard let day = draft.scheduledDay ?? occurrence.scheduledDay else {
                        return
                    }
                    todos[index].setOccurrenceOverride(
                        TodoOccurrenceOverride(
                            occurrenceID: occurrenceID,
                            title: title,
                            scheduledDay: day,
                            startTime: draft.startTime,
                            notificationEnabled: draft.notificationEnabled,
                            notificationTime: effectiveNotificationTime(for: draft),
                            completionFollowUpEnabled: draft.completionFollowUpEnabled
                        )
                    )
                case .thisAndFuture:
                    guard let baseDay = occurrence.baseScheduledDay,
                          let seriesEnd = baseDay.addingDays(-1),
                          let newStartDay = draft.scheduledDay ?? occurrence.scheduledDay else {
                        return
                    }
                    todos[index].seriesEndDay = seriesEnd
                    todos.append(
                        TodoRecord(
                            title: title,
                            scheduledDay: newStartDay,
                            startTime: draft.startTime,
                            recurrence: draft.recurrence,
                            notificationEnabled: draft.notificationEnabled,
                            notificationTime: effectiveNotificationTime(for: draft),
                            completionFollowUpEnabled: draft.completionFollowUpEnabled
                        )
                    )
                }
            } else {
                todos[index].title = title
                todos[index].scheduledDay = draft.scheduledDay
                todos[index].startTime = draft.scheduledDay == nil
                    ? nil
                    : draft.startTime
                todos[index].recurrence = draft.scheduledDay == nil
                    ? .none
                    : draft.recurrence
                todos[index].notificationEnabled = draft.scheduledDay != nil
                    && draft.notificationEnabled
                todos[index].notificationTime = effectiveNotificationTime(for: draft)
                todos[index].completionFollowUpEnabled = draft.scheduledDay != nil
                    && draft.completionFollowUpEnabled
                todos[index].seriesEndDay = nil
                if draft.recurrence == .monthly {
                    todos[index].completedAt = nil
                }
            }
        } else {
            todos.append(
                TodoRecord(
                    title: title,
                    scheduledDay: draft.scheduledDay,
                    startTime: draft.startTime,
                    recurrence: draft.recurrence,
                    notificationEnabled: draft.notificationEnabled,
                    notificationTime: effectiveNotificationTime(for: draft),
                    completionFollowUpEnabled: draft.completionFollowUpEnabled
                )
            )
        }

        todoDraft = nil
        _ = normalizeRecurringTodoStates()
        persistData()
        await synchronizeNotifications()
    }

    private func effectiveNotificationTime(
        for draft: TodoEditorDraft
    ) -> LocalTime? {
        guard draft.scheduledDay != nil, draft.notificationEnabled else {
            return nil
        }
        return draft.notificationTime ?? draft.startTime ?? .nineAM
    }

    func toggle(_ occurrence: TodoOccurrence) {
        guard !occurrence.isSkipped,
              let index = todos.firstIndex(where: { $0.id == occurrence.todoID }) else {
            return
        }
        if occurrence.isRecurring,
           let anchor = todos[index].scheduledDay,
           todos[index].occurrences(from: anchor, through: currentDay).last?.id
            != occurrence.id {
            return
        }
        todos[index].setOccurrenceCompleted(
            occurrence.id,
            completed: !occurrence.isCompleted
        )
        persistData()
        Task { await synchronizeNotifications() }
    }

    func toggle(_ todo: TodoRecord) {
        guard let occurrence = todo.occurrence(for: .once(todoID: todo.id)) else {
            return
        }
        toggle(occurrence)
    }

    func updateTodoTitle(_ todo: TodoRecord, title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            delete(todo)
            return
        }
        guard
            let index = todos.firstIndex(where: { $0.id == todo.id }),
            todos[index].title != trimmedTitle
        else {
            return
        }
        todos[index].rename(trimmedTitle)
        persistData()
        Task { await synchronizeNotifications() }
    }

    func delete(_ todo: TodoRecord) {
        todos.removeAll { $0.id == todo.id }
        persistData()
        Task { await synchronizeNotifications() }
    }

    func delete(_ occurrence: TodoOccurrence) {
        if occurrence.isRecurring {
            pendingTodoDeletion = occurrence
            return
        }
        todos.removeAll { $0.id == occurrence.todoID }
        persistData()
        Task { await synchronizeNotifications() }
    }

    func confirmTodoDeletion(scope: TodoEditScope) {
        guard let occurrence = pendingTodoDeletion,
              let index = todos.firstIndex(where: { $0.id == occurrence.todoID }) else {
            pendingTodoDeletion = nil
            return
        }
        switch scope {
        case .onlyThis:
            todos[index].markOccurrenceSkipped(occurrence.id)
        case .thisAndFuture:
            if let baseDay = occurrence.baseScheduledDay,
               let seriesEnd = baseDay.addingDays(-1) {
                todos[index].seriesEndDay = seriesEnd
            }
        }
        pendingTodoDeletion = nil
        persistData()
        Task { await synchronizeNotifications() }
    }

    func addBookmarkForActivePage() {
        guard let url = browser.activeTab?.url else { return }
        let normalized = URLResolver.normalized(url)
        if let existing = bookmarks.first(where: {
            URLResolver.normalized($0.url) == normalized
        }) {
            bookmarks.removeAll { $0.id == existing.id }
        } else {
            bookmarks.append(
                BookmarkRecord(
                    title: browser.activeTab?.displayTitle ?? url.host() ?? url.absoluteString,
                    url: url
                )
            )
        }
        persistData()
    }

    func removeBookmark(_ bookmark: BookmarkRecord) {
        bookmarks.removeAll { $0.id == bookmark.id }
        persistData()
    }

    func isBookmarked(_ url: URL?) -> Bool {
        guard let url else { return false }
        let normalized = URLResolver.normalized(url)
        return bookmarks.contains {
            URLResolver.normalized($0.url) == normalized
        }
    }

    func updateLanguage(_ language: AppLanguage) {
        preferences.language = language
        savePreferences()
        Task { await synchronizeNotifications() }
    }

    func updateAppearance(_ appearance: AppearanceMode) {
        preferences.appearance = appearance
        savePreferences()
        applyAppearance()
    }

    func updateBrowserDarkMode(_ enabled: Bool) {
        preferences.browserDarkMode = enabled
        savePreferences()
        browser.setDarkMode(enabled)
    }

    func updateGlobalShortcut(_ shortcut: String) {
        let normalized = ShortcutParser.parse(shortcut)?.storageValue
            ?? AppPreferences.defaults.globalShortcut
        if hotKeyManager.register(shortcut: normalized, handler: toggleMainWindow) {
            preferences.globalShortcut = normalized
            savePreferences()
        } else {
            preferences.globalShortcut = AppPreferences.defaults.globalShortcut
            savePreferences()
            registerGlobalShortcut(preferences.globalShortcut)
            statusMessage = text("status.shortcutUnavailable")
        }
    }

    func refreshNotificationState() async {
        notificationState = await scheduler.authorizationState()
    }

    @discardableResult
    func previewReminder(content: String) async -> Bool {
        let trimmedContent = content.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedContent.isEmpty else { return false }

        let allowed = await scheduler.requestAuthorization()
        await refreshNotificationState()
        guard allowed else {
            statusMessage = text("status.permissionDenied")
            return false
        }

        let delivered = await scheduler.deliverPreview(body: trimmedContent)
        if !delivered {
            statusMessage = text("reminders.try.failed.body")
        }
        return delivered
    }

    func openNotificationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func toggleMainWindow() {
        guard let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue == "moment.main"
        }) else {
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        if window.isVisible && window.isKeyWindow {
            window.orderOut(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    func showMainWindow() {
        guard let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue == "moment.main"
        }) else {
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func handleCloseCommand() {
        if workspace == .browser {
            browser.closeActiveTab()
        } else {
            NSApp.windows.first(where: {
                $0.identifier?.rawValue == "moment.main"
            })?.orderOut(nil)
        }
    }

    func resynchronizeAfterWake() {
        currentDay = LocalDay(date: .now)
        if normalizeRecurringTodoStates() {
            persistData()
        }
        Task { await synchronizeNotifications() }
    }

    private func handleReminderFired(id: String, at date: Date) {
        guard
            let index = reminders.firstIndex(where: { $0.id == id }),
            reminders[index].isEnabled
        else {
            return
        }
        reminders[index].settle(at: date)
        persistData()
    }

    func synchronizeNotifications() async {
        let current = reminders
        await scheduler.synchronize(
            current,
            todos: todos,
            life: life,
            language: preferences.language
        ) { [weak self] id, date in
            Task { @MainActor in
                self?.handleReminderFired(id: id, at: date)
            }
        }
    }

    func persistData() {
        let snapshot = PersistedAppData(
            version: PersistedAppData.currentVersion,
            reminders: reminders,
            bookmarks: bookmarks,
            todos: todos,
            life: life
        )
        Task {
            do {
                try await dataStore.saveData(snapshot)
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func commitLife(_ updated: LifeData, reschedule: Bool = true) {
        life = updated
        persistData()
        if reschedule {
            Task { await synchronizeNotifications() }
        }
    }

    func requestNotificationPermissionIfNeeded() async {
        let allowed = await scheduler.requestAuthorization()
        await refreshNotificationState()
        if !allowed {
            statusMessage = text("status.permissionDenied")
        }
        await synchronizeNotifications()
    }

    func handleNotificationSelection(_ userInfo: [AnyHashable: Any]) {
        guard dataLoaded else {
            pendingNotificationSelections.append(userInfo)
            return
        }
        processNotificationSelection(userInfo)
    }

    private func processNotificationSelection(_ userInfo: [AnyHashable: Any]) {
        var shouldShowWindow = true
        switch userInfo["route"] as? String {
        case "inventory":
            workspace = .inventory
            showingInventoryReview = true
        case "expense":
            workspace = .expenses
            highlightedExpenseID = userInfo["expenseID"] as? String
        case "todos":
            workspace = .todos
            todoViewMode = .todos
            if let rawOccurrenceID = userInfo["occurrenceID"] as? String,
               let occurrenceID = TodoOccurrenceID(rawValue: rawOccurrenceID) {
                highlightedTodoOccurrenceID = occurrenceID
                if userInfo["actionIdentifier"] as? String
                    == "moment.todo.complete",
                   let index = todos.firstIndex(where: {
                       $0.id == occurrenceID.todoID
                   }), todos[index].occurrence(for: occurrenceID) != nil,
                   todos[index].state(for: occurrenceID) != .skipped {
                    todos[index].setOccurrenceCompleted(
                        occurrenceID,
                        completed: true
                    )
                    persistData()
                    Task { await synchronizeNotifications() }
                    shouldShowWindow = false
                }
            }
        default:
            break
        }
        if shouldShowWindow {
            showMainWindow()
        }
    }

    @discardableResult
    private func normalizeRecurringTodoStates(
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        let today = LocalDay(date: now, calendar: calendar)
        var changed = false
        for index in todos.indices where todos[index].recurrence == .monthly {
            guard let anchor = todos[index].scheduledDay else { continue }
            let dueOccurrences = todos[index].occurrences(
                from: anchor,
                through: today,
                calendar: calendar
            )
            guard dueOccurrences.count > 1 else { continue }
            for occurrence in dueOccurrences.dropLast()
            where occurrence.state == .active {
                todos[index].markOccurrenceSkipped(occurrence.id, at: now)
                changed = true
            }
        }
        return changed
    }

    private func todoOccurrenceSort(
        _ lhs: TodoOccurrence,
        _ rhs: TodoOccurrence
    ) -> Bool {
        func group(_ occurrence: TodoOccurrence) -> Int {
            if occurrence.isSkipped { return 5 }
            if occurrence.isCompleted { return 4 }
            guard let day = occurrence.scheduledDay else { return 0 }
            if day < currentDay { return 1 }
            return occurrence.startTime == nil ? 2 : 3
        }

        let lhsGroup = group(lhs)
        let rhsGroup = group(rhs)
        if lhsGroup != rhsGroup { return lhsGroup < rhsGroup }
        switch (lhs.scheduledDay, rhs.scheduledDay) {
        case let (.some(lhsDay), .some(rhsDay)) where lhsDay != rhsDay:
            return lhsDay < rhsDay
        case (.none, .some):
            return true
        case (.some, .none):
            return false
        default:
            break
        }
        switch (lhs.startTime, rhs.startTime) {
        case let (.some(lhsTime), .some(rhsTime)) where lhsTime != rhsTime:
            return lhsTime < rhsTime
        case (.none, .some):
            return true
        case (.some, .none):
            return false
        default:
            return lhs.title.localizedStandardCompare(rhs.title)
                == .orderedAscending
        }
    }

    func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        let dateStamp = ISO8601DateFormatter().string(from: .now).prefix(10)
        panel.nameFieldStringValue = "Zaki-Backup-\(dateStamp).json"

        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }

        let snapshot = PersistedAppData(
            version: PersistedAppData.currentVersion,
            reminders: reminders,
            bookmarks: bookmarks,
            todos: todos,
            life: life
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            try encoder.encode(snapshot).write(to: destination, options: .atomic)
            statusMessage = text("status.backupExported")
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func savePreferences() {
        preferencesStore.save(preferences)
    }

    private func applyAppearance() {
        switch preferences.appearance {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func registerGlobalShortcut(_ shortcut: String) {
        if !hotKeyManager.register(shortcut: shortcut, handler: toggleMainWindow) {
            _ = hotKeyManager.register(
                shortcut: AppPreferences.defaults.globalShortcut,
                handler: toggleMainWindow
            )
        }
    }
}
