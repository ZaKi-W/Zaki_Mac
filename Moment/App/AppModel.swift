import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var workspace: Workspace = .reminders
    @Published private(set) var reminders: [ReminderRecord] = []
    @Published private(set) var bookmarks: [BookmarkRecord] = []
    @Published private(set) var preferences: AppPreferences
    @Published var reminderDraft: ReminderDraft?
    @Published var pendingDeletion: ReminderRecord?
    @Published var statusMessage: String?
    @Published private(set) var notificationState: NotificationAuthorizationState = .unknown

    let browser = BrowserController()

    private let dataStore: JSONAppDataStore
    private let migrator: LegacyMigrator
    private let preferencesStore: PreferencesStore
    private let scheduler: ReminderScheduler
    private let hotKeyManager: GlobalHotKeyManager
    private var started = false

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
                applyAppearance()
                browser.setDarkMode(preferences.browserDarkMode)
                registerGlobalShortcut(preferences.globalShortcut)
                await refreshNotificationState()
                await synchronizeReminders()
            } catch {
                reminders = []
                bookmarks = []
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
        await synchronizeReminders()
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
            await synchronizeReminders()
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
        Task { await synchronizeReminders() }
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
        Task { await synchronizeReminders() }
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

    private func synchronizeReminders() async {
        let current = reminders
        await scheduler.synchronize(current) { [weak self] id, date in
            Task { @MainActor in
                self?.handleReminderFired(id: id, at: date)
            }
        }
    }

    private func persistData() {
        let snapshot = PersistedAppData(
            version: 1,
            reminders: reminders,
            bookmarks: bookmarks
        )
        Task {
            do {
                try await dataStore.saveData(snapshot)
            } catch {
                statusMessage = error.localizedDescription
            }
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
