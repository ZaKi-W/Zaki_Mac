import SwiftUI

struct MomentCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(model.text("todos.new")) {
                model.openNewTodo()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

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
            Button(model.text("sidebar.dashboard")) {
                model.workspace = .dashboard
            }
            .keyboardShortcut("1", modifiers: .command)

            Button(model.text("sidebar.inventory")) {
                model.workspace = .inventory
            }
            .keyboardShortcut("2", modifiers: .command)

            Button(model.text("sidebar.assets")) {
                model.workspace = .assets
            }
            .keyboardShortcut("3", modifiers: .command)

            Button(model.text("sidebar.expenses")) {
                model.workspace = .expenses
            }
            .keyboardShortcut("4", modifiers: .command)

            Button(model.text("sidebar.todos")) {
                model.workspace = .todos
            }

            Button(model.text("sidebar.reminders")) {
                model.workspace = .reminders
            }
            .keyboardShortcut("5", modifiers: .command)

            Button(model.text("sidebar.browser")) {
                model.workspace = .browser
            }
            .keyboardShortcut("6", modifiers: .command)
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
