import SwiftUI

struct TodoWorkspace: View {
    @ObservedObject var model: AppModel
    @State private var selectedID: String?
    @State private var newTodoTitle = ""
    @FocusState private var isQuickEntryFocused: Bool

    private var openTodos: [TodoRecord] {
        model.todos
            .filter { !$0.isCompleted }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var completedTodos: [TodoRecord] {
        model.todos
            .filter(\.isCompleted)
            .sorted {
                ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt)
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            quickEntry
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            Divider()

            Group {
                if model.todos.isEmpty {
                    ContentUnavailableView {
                        Label(
                            model.text("todos.empty.title"),
                            systemImage: "checklist"
                        )
                    } description: {
                        Text(model.text("todos.empty.body"))
                    }
                } else {
                    List(selection: $selectedID) {
                        todoSection(
                            title: model.text("todos.open"),
                            todos: openTodos
                        )
                        todoSection(
                            title: model.text("todos.completed"),
                            todos: completedTodos
                        )
                    }
                    .listStyle(.inset)
                    .animation(
                        .spring(response: 0.42, dampingFraction: 0.84),
                        value: model.todos
                    )
                    .onDeleteCommand {
                        guard
                            let selectedID,
                            let todo = model.todos.first(where: { $0.id == selectedID })
                        else {
                            return
                        }
                        withAnimation(.snappy) {
                            model.delete(todo)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle(model.text("todos.title"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isQuickEntryFocused = true
                } label: {
                    Label(model.text("todos.new"), systemImage: "plus")
                }
                .help(model.text("todos.new"))
            }
        }
        .onAppear {
            isQuickEntryFocused = true
        }
        .onChange(of: model.todoEntryFocusRequest) {
            isQuickEntryFocused = true
        }
    }

    private var quickEntry: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)

            TextField(
                model.text("todos.quickAdd"),
                text: $newTodoTitle,
                prompt: Text(model.text("todos.quickAdd.placeholder"))
            )
            .textFieldStyle(.plain)
            .focused($isQuickEntryFocused)
            .onSubmit(submitTodo)

            Button(action: submitTodo) {
                Image(systemName: "arrow.turn.down.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(model.text("todos.quickAdd.hint"))
            .disabled(
                newTodoTitle
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func todoSection(
        title: String,
        todos: [TodoRecord]
    ) -> some View {
        if !todos.isEmpty {
            Section {
                ForEach(todos) { todo in
                    InlineTodoRow(model: model, todo: todo)
                        .tag(todo.id)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            )
                        )
                }
            } header: {
                HStack {
                    Text(title)
                    Spacer()
                    Text(todos.count, format: .number)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
        }
    }

    private func submitTodo() {
        guard model.addTodo(title: newTodoTitle) else { return }
        withAnimation(.snappy) {
            newTodoTitle = ""
        }
        isQuickEntryFocused = true
    }
}

private struct InlineTodoRow: View {
    @ObservedObject var model: AppModel
    let todo: TodoRecord
    @State private var title: String
    @State private var isHovering = false
    @FocusState private var isEditing: Bool

    init(model: AppModel, todo: TodoRecord) {
        self.model = model
        self.todo = todo
        _title = State(initialValue: todo.title)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                commitTitle()
                withAnimation(
                    .spring(response: 0.42, dampingFraction: 0.78)
                ) {
                    model.toggle(todo)
                }
            } label: {
                Image(
                    systemName: todo.isCompleted
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    todo.isCompleted ? Color.green : Color.accentColor
                )
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: todo.isCompleted)
            }
            .buttonStyle(.plain)
            .help(
                todo.isCompleted
                    ? model.text("todos.markOpen")
                    : model.text("todos.markCompleted")
            )

            TextField("", text: $title)
                .textFieldStyle(.plain)
                .focused($isEditing)
                .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                .strikethrough(todo.isCompleted)
                .onSubmit(commitTitle)
                .onChange(of: isEditing) { _, editing in
                    if !editing {
                        commitTitle()
                    }
                }

            if isHovering {
                Button(role: .destructive) {
                    withAnimation(.snappy) {
                        model.delete(todo)
                    }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(model.text("todos.delete"))
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 5)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .onChange(of: todo.title) { _, updatedTitle in
            if !isEditing {
                title = updatedTitle
            }
        }
        .contextMenu {
            Button {
                commitTitle()
                withAnimation(.snappy) {
                    model.toggle(todo)
                }
            } label: {
                Label(
                    todo.isCompleted
                        ? model.text("todos.markOpen")
                        : model.text("todos.markCompleted"),
                    systemImage: todo.isCompleted
                        ? "arrow.uturn.backward.circle"
                        : "checkmark.circle"
                )
            }
            Divider()
            Button(role: .destructive) {
                withAnimation(.snappy) {
                    model.delete(todo)
                }
            } label: {
                Label(model.text("todos.delete"), systemImage: "trash")
            }
        }
    }

    private func commitTitle() {
        model.updateTodoTitle(todo, title: title)
    }
}
