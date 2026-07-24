import SwiftUI

struct MomentCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(model.text("reminders.new")) {
                model.openNewReminder()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button(model.text("browser.newTab")) {
                model.workspace = .browser
                model.browser.createTab()
            }
            .keyboardShortcut("t", modifiers: .command)
        }

        CommandGroup(after: .sidebar) {
            Divider()
            Button(model.text("sidebar.reminders")) {
                model.workspace = .reminders
            }
            .keyboardShortcut("1", modifiers: .command)

            Button(model.text("sidebar.browser")) {
                model.workspace = .browser
            }
            .keyboardShortcut("2", modifiers: .command)
        }

        CommandMenu(model.text("sidebar.browser")) {
            Button(model.text("browser.newTab")) {
                model.workspace = .browser
                model.browser.createTab()
            }
            .keyboardShortcut("t", modifiers: .command)

            Button(model.text("browser.reload")) {
                model.browser.activeTab?.reload()
            }
            .keyboardShortcut("r", modifiers: .command)

            Button(model.text("browser.address")) {
                model.workspace = .browser
                model.browser.focusAddressToken += 1
            }
            .keyboardShortcut("l", modifiers: .command)

            Button("Close Tab") {
                model.browser.closeActiveTab()
            }
            .keyboardShortcut("w", modifiers: .command)
        }
    }
}
