import AppKit
import SwiftUI

@main
struct MomentApp: App {
    @NSApplicationDelegateAdaptor(MomentAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Window("Moment", id: "main") {
            ContentView(model: model)
                .environment(\.locale, model.locale)
                .preferredColorScheme(model.preferredColorScheme)
        }
        .defaultSize(width: 1_100, height: 720)
        .windowStyle(.automatic)
        .commands {
            MomentCommands(model: model)
        }

        Settings {
            SettingsView(model: model)
                .environment(\.locale, model.locale)
                .preferredColorScheme(model.preferredColorScheme)
        }
    }
}

@MainActor
final class MomentAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.start()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showMainWindow),
            name: .momentShowMainWindow,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCloseCommand),
            name: .momentCloseCommand,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNotificationSelection(_:)),
            name: .momentNotificationSelection,
            object: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        AppModel.shared.showMainWindow()
        return true
    }

    @objc private func didWake() {
        AppModel.shared.resynchronizeAfterWake()
    }

    @objc private func showMainWindow() {
        AppModel.shared.showMainWindow()
    }

    @objc private func handleCloseCommand() {
        AppModel.shared.handleCloseCommand()
    }

    @objc private func handleNotificationSelection(_ notification: Notification) {
        AppModel.shared.handleNotificationSelection(notification.userInfo ?? [:])
    }
}

extension Notification.Name {
    static let momentShowMainWindow = Notification.Name("moment.show-main-window")
    static let momentCloseCommand = Notification.Name("moment.close-command")
    static let momentNotificationSelection = Notification.Name(
        "moment.notification-selection"
    )
}
