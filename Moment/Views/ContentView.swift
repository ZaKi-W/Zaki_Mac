import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.workspace) {
                Section(model.text("sidebar.life")) {
                    Label(
                        model.text("sidebar.dashboard"),
                        systemImage: "square.grid.2x2"
                    )
                    .tag(Workspace.dashboard)

                    Label(
                        model.text("sidebar.inventory"),
                        systemImage: "shippingbox"
                    )
                    .tag(Workspace.inventory)

                    Label(
                        model.text("sidebar.assets"),
                        systemImage: "banknote"
                    )
                    .tag(Workspace.assets)

                    Label(
                        model.text("sidebar.expenses"),
                        systemImage: "creditcard"
                    )
                    .tag(Workspace.expenses)
                }

                Section(model.text("sidebar.tools")) {
                    Label(
                        model.text("sidebar.todos"),
                        systemImage: "checklist"
                    )
                    .tag(Workspace.todos)

                    Label(
                        model.text("sidebar.reminders"),
                        systemImage: "bell.badge"
                    )
                    .tag(Workspace.reminders)

                    Label(
                        model.text("sidebar.aiHot"),
                        systemImage: "newspaper"
                    )
                    .tag(Workspace.aiHot)

                    Label(
                        model.text("sidebar.browser"),
                        systemImage: "safari"
                    )
                    .tag(Workspace.browser)
                }
            }
            .navigationTitle(model.text("app.name"))
            .navigationSplitViewColumnWidth(min: 170, ideal: 210, max: 260)
        } detail: {
            switch model.workspace {
            case .dashboard:
                DashboardWorkspace(model: model)
            case .inventory:
                InventoryWorkspace(model: model)
            case .assets:
                AssetWorkspace(model: model)
            case .expenses:
                ExpenseWorkspace(model: model)
            case .todos:
                TodoWorkspace(model: model)
            case .reminders:
                ReminderWorkspace(model: model)
            case .aiHot:
                AIHotWorkspace(model: model, controller: model.aiHot)
            case .browser:
                BrowserWorkspace(model: model, controller: model.browser)
            }
        }
        .background(MainWindowBehavior().frame(width: 0, height: 0))
        .sheet(item: $model.reminderDraft) { draft in
            ReminderEditorView(model: model, initialDraft: draft)
        }
        .sheet(isPresented: $model.showingInventoryReview) {
            InventoryReviewView(model: model)
        }
        .alert(
            model.text("reminders.delete.confirm"),
            isPresented: Binding(
                get: { model.pendingDeletion != nil },
                set: { if !$0 { model.pendingDeletion = nil } }
            ),
            presenting: model.pendingDeletion
        ) { _ in
            Button(model.text("common.cancel"), role: .cancel) {
                model.pendingDeletion = nil
            }
            Button(model.text("reminders.delete"), role: .destructive) {
                model.confirmDelete()
            }
        }
        .overlay(alignment: .top) {
            if let status = model.statusMessage {
                StatusBanner(message: status) {
                    model.statusMessage = nil
                }
                .padding(.top, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: model.statusMessage)
    }
}

private struct StatusBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
            Text(message)
                .lineLimit(2)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(
                Color(nsColor: .separatorColor).opacity(0.7),
                lineWidth: 0.5
            )
        }
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }
}
