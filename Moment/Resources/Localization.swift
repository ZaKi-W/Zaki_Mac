import Foundation

enum L10n {
    static func text(_ key: String, _ language: AppLanguage) -> String {
        let resource = language == .zh ? "zh-Hans" : "en"
        guard
            let path = Bundle.main.path(forResource: resource, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            return fallback[key] ?? key
        }
        return bundle.localizedString(
            forKey: key,
            value: fallback[key],
            table: "Localizable"
        )
    }

    private static let fallback: [String: String] = [
        "app.name": "Moment",
        "sidebar.reminders": "Reminders",
        "sidebar.browser": "Browser",
        "reminders.title": "Reminders",
        "reminders.new": "New Reminder",
        "reminders.active": "Active",
        "reminders.paused": "Paused",
        "reminders.completed": "Completed",
        "reminders.empty.title": "No reminders yet",
        "reminders.empty.body": "Create a quiet prompt for the moments that matter.",
        "reminders.next": "Next",
        "reminders.every": "Every",
        "reminders.once": "Once",
        "reminders.repeat": "Repeat",
        "reminders.pause": "Pause",
        "reminders.resume": "Resume",
        "reminders.edit": "Edit",
        "reminders.delete": "Delete",
        "reminders.delete.confirm": "Delete this reminder?",
        "editor.new": "New Reminder",
        "editor.edit": "Edit Reminder",
        "editor.content": "Reminder",
        "editor.content.placeholder": "Take a moment to stretch",
        "editor.interval": "Interval",
        "editor.hours": "Hours",
        "editor.minutes": "Minutes",
        "editor.seconds": "Seconds",
        "editor.mode": "Mode",
        "editor.enabled": "Enable immediately",
        "common.cancel": "Cancel",
        "common.save": "Save",
        "common.create": "Create",
        "browser.address": "Search or enter website name",
        "browser.newTab": "New Tab",
        "browser.start": "Start Page",
        "browser.favorites": "Favorites",
        "browser.bookmarks": "Bookmarks",
        "browser.back": "Back",
        "browser.forward": "Forward",
        "browser.reload": "Reload",
        "browser.home": "Start Page",
        "browser.bookmark": "Add Bookmark",
        "browser.unbookmark": "Remove Bookmark",
        "browser.dark": "Website Dark Mode",
        "settings.general": "General",
        "settings.shortcuts": "Shortcuts",
        "settings.about": "About",
        "settings.appearance": "Appearance",
        "settings.system": "System",
        "settings.light": "Light",
        "settings.dark": "Dark",
        "settings.language": "Language",
        "settings.chinese": "简体中文",
        "settings.english": "English",
        "settings.browserDark": "Dark website adaptation",
        "settings.globalShortcut": "Show or hide Moment",
        "settings.shortcutHint": "Click the recorder, then press a shortcut.",
        "settings.notification": "Notifications",
        "settings.notification.allowed": "Allowed",
        "settings.notification.denied": "Not allowed",
        "settings.notification.unknown": "Not requested",
        "settings.openSystemSettings": "Open System Settings",
        "settings.version": "Version",
        "status.migrated": "Your reminders and bookmarks were imported.",
        "status.permissionDenied": "Notifications are disabled. Enable them in System Settings.",
        "status.shortcutUnavailable": "That shortcut is unavailable; ⌘⇧H is active instead."
    ]
}
