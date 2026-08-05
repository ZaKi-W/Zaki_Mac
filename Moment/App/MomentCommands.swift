import SwiftUI

struct MomentCommands: Commands {
    @ObservedObject var model: AppModel
    @ObservedObject private var files: FileBrowserController

    init(model: AppModel) {
        self.model = model
        files = model.files
    }

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
            .disabled(model.workspace != .browser)
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

            Button(model.text("sidebar.files")) {
                model.workspace = .files
            }
            .keyboardShortcut("8", modifiers: .command)

            Button(model.text("sidebar.aiHot")) {
                model.workspace = .aiHot
            }
            .keyboardShortcut("7", modifiers: .command)

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
            .disabled(model.workspace != .browser)

            Button(model.text("browser.address")) {
                model.workspace = .browser
                model.browser.focusAddressToken += 1
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(model.workspace != .browser)

            Button("Close Tab") {
                model.browser.closeActiveTab()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(model.workspace != .browser)
        }

        CommandMenu(model.text("sidebar.files")) {
            Button(model.text("file.open")) {
                model.workspace = .files
                files.openSelection()
            }
            .keyboardShortcut("o", modifiers: .command)

            Divider()

            Button(model.text("file.copy")) {
                files.copySelectionToClipboard()
            }
            .keyboardShortcut("c", modifiers: .command)
            .disabled(model.workspace != .files || files.selection.isEmpty)

            Button(model.text("file.paste")) {
                files.requestPaste(moving: false)
            }
            .keyboardShortcut("v", modifiers: .command)
            .disabled(model.workspace != .files || !files.canPaste)

            Button(model.text("file.pasteMove")) {
                files.requestPaste(moving: true)
            }
            .keyboardShortcut("v", modifiers: [.command, .option])
            .disabled(model.workspace != .files || !files.canPaste)

            Divider()

            Button(model.text("file.refresh")) {
                Task { await files.refresh() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.workspace != .files)
        }
    }
}
