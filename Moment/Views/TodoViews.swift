import SwiftUI

struct TodoWorkspace: View {
    @ObservedObject var model: AppModel
    @State private var newTodoTitle = ""
    @State private var selectedDay = TodoDateSupport.localDay(from: .now)
    @State private var visibleMonth = TodoDateSupport.startOfMonth(containing: .now)
    @FocusState private var isQuickEntryFocused: Bool

    private var quickAddDay: LocalDay? {
        switch model.todoViewMode {
        case .todos:
            nil
        case .calendar:
            selectedDay
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            modeBar
            Divider()
            quickEntry
            Divider()

            Group {
                switch model.todoViewMode {
                case .todos:
                    AllTodoView(model: model)
                case .calendar:
                    CalendarTodoView(
                        model: model,
                        selectedDay: $selectedDay,
                        visibleMonth: $visibleMonth
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle(model.text("todos.title"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.openNewTodo(for: quickAddDay)
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
        .onChange(of: model.todoViewMode) {
            isQuickEntryFocused = true
        }
    }

    private var modeBar: some View {
        HStack {
            Picker(model.text("todos.view"), selection: $model.todoViewMode) {
                Label(model.text("todos.view.todos"), systemImage: "checklist")
                    .tag(TodoViewMode.todos)
                Label(model.text("todos.view.calendar"), systemImage: "calendar")
                    .tag(TodoViewMode.calendar)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)

            Spacer()

            if model.todoViewMode == .calendar {
                Button(model.text("todos.calendar.today")) {
                    let today = TodoDateSupport.localDay(from: .now)
                    selectedDay = today
                    visibleMonth = TodoDateSupport.startOfMonth(containing: .now)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var quickEntry: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)

            TextField(
                model.text("todos.quickAdd"),
                text: $newTodoTitle,
                prompt: Text(quickAddPrompt)
            )
            .textFieldStyle(.plain)
            .focused($isQuickEntryFocused)
            .onSubmit(submitTodo)

            if let quickAddDay {
                Label(
                    TodoDateSupport.shortDate(quickAddDay, locale: model.locale),
                    systemImage: "calendar"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Button(action: submitTodo) {
                Image(systemName: "arrow.turn.down.left")
            }
            .buttonStyle(HoverIconButtonStyle(kind: .accent, size: 26))
            .help(model.text("todos.quickAdd.hint"))
            .disabled(trimmedNewTitle.isEmpty)
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var quickAddPrompt: String {
        switch model.todoViewMode {
        case .todos:
            model.text("todos.quickAdd.unscheduled.placeholder")
        case .calendar:
            model.text("todos.quickAdd.day.placeholder")
        }
    }

    private var trimmedNewTitle: String {
        newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submitTodo() {
        guard model.quickAddTodo(
            title: trimmedNewTitle,
            scheduledDay: quickAddDay
        ) else {
            return
        }
        withAnimation(.snappy) {
            newTodoTitle = ""
        }
        isQuickEntryFocused = true
    }
}

private struct AllTodoView: View {
    @ObservedObject var model: AppModel

    private var sections: [TodoListSection] {
        let occurrences = model.allTodoOccurrences
        let today = TodoDateSupport.localDay(from: .now)
        let todayItems = model.todayOccurrences.filter { !$0.isSkipped }
        let todayOccurrenceIDs = Set(todayItems.map(\.id))
        let todayTodoIDs = Set(todayItems.map(\.todoID))

        let unscheduled = occurrences.filter {
            $0.scheduledDay == nil && !$0.isCompleted && !$0.isSkipped
        }
        let recurringCandidates = occurrences.filter {
            $0.isRecurring
                && !$0.isCompleted
                && !$0.isSkipped
                && !todayTodoIDs.contains($0.todoID)
        }
        let recurring = Dictionary(grouping: recurringCandidates, by: \.todoID)
            .values
            .compactMap { occurrences in
                occurrences
                    .filter {
                        guard let day = $0.scheduledDay else { return false }
                        return TodoDateSupport.compare(day, today) != .orderedAscending
                    }
                    .min(by: TodoDateSupport.occurrenceDayAscending)
                    ?? occurrences.max(by: TodoDateSupport.occurrenceDayAscending)
            }
            .sorted(by: TodoDateSupport.occurrenceDayAscending)
        let scheduled = occurrences.filter {
            guard let day = $0.scheduledDay else { return false }
            return !$0.isRecurring
                && !$0.isCompleted
                && !$0.isSkipped
                && TodoDateSupport.compare(day, today) == .orderedDescending
        }
        let completed = occurrences.filter {
            $0.isCompleted && !todayOccurrenceIDs.contains($0.id)
        }
        let skipped = occurrences.filter(\.isSkipped)

        return [
            TodoListSection(
                id: "today",
                title: model.text("todos.section.today"),
                symbol: "sun.max.fill",
                tint: .accentColor,
                items: todayItems
            ),
            TodoListSection(
                id: "unscheduled",
                title: model.text("todos.section.unscheduled"),
                symbol: "tray",
                tint: .secondary,
                items: unscheduled
            ),
            TodoListSection(
                id: "scheduled",
                title: model.text("todos.section.upcoming"),
                symbol: "calendar",
                tint: .accentColor,
                items: scheduled
            ),
            TodoListSection(
                id: "recurring",
                title: model.text("todos.section.recurring"),
                symbol: "repeat",
                tint: .orange,
                items: recurring
            ),
            TodoListSection(
                id: "completed",
                title: model.text("todos.completed"),
                symbol: "checkmark.circle",
                tint: .green,
                items: completed
            ),
            TodoListSection(
                id: "skipped",
                title: model.text("todos.section.skipped"),
                symbol: "forward.circle",
                tint: .secondary,
                items: skipped
            )
        ]
    }

    var body: some View {
        TodoSectionList(
            model: model,
            sections: sections,
            emptyTitle: model.text("todos.empty.title"),
            emptyBody: model.text("todos.empty.body"),
            emptySymbol: "checklist"
        )
    }
}

private struct TodoSectionList: View {
    @ObservedObject var model: AppModel
    let sections: [TodoListSection]
    let emptyTitle: String
    let emptyBody: String
    let emptySymbol: String

    private var isEmpty: Bool {
        sections.allSatisfy(\.items.isEmpty)
    }

    var body: some View {
        if isEmpty {
            ContentUnavailableView {
                Label(emptyTitle, systemImage: emptySymbol)
            } description: {
                Text(emptyBody)
            }
        } else {
            List {
                ForEach(sections) { section in
                    if !section.items.isEmpty {
                        Section {
                            ForEach(section.items) { occurrence in
                                TodoOccurrenceRow(
                                    model: model,
                                    occurrence: occurrence
                                )
                            }
                        } header: {
                            TodoSectionHeader(section: section)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}

private struct TodoListSection: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let tint: Color
    let items: [TodoOccurrence]
}

private struct TodoSectionHeader: View {
    let section: TodoListSection

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: section.symbol)
                .foregroundStyle(section.tint)
            Text(section.title)
            Spacer()
            Text(section.items.count, format: .number)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }
}

private struct CalendarTodoView: View {
    @ObservedObject var model: AppModel
    @Binding var selectedDay: LocalDay
    @Binding var visibleMonth: Date

    private let dayColumns = Array(
        repeating: GridItem(.flexible(minimum: 34), spacing: 4),
        count: 7
    )

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                calendar
                    .frame(minWidth: 390, idealWidth: proxy.size.width * 0.58)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                Divider()

                selectedDayList
                    .frame(
                        minWidth: 280,
                        idealWidth: proxy.size.width * 0.42,
                        maxWidth: 430,
                        maxHeight: .infinity,
                        alignment: .top
                    )
            }
        }
    }

    private var calendar: some View {
        VStack(spacing: 14) {
            HStack {
                Button {
                    changeMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(HoverIconButtonStyle())
                .help(model.text("todos.calendar.previousMonth"))

                Text(TodoDateSupport.monthTitle(visibleMonth, locale: model.locale))
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity)

                Button {
                    changeMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(HoverIconButtonStyle())
                .help(model.text("todos.calendar.nextMonth"))
            }

            LazyVGrid(columns: dayColumns, spacing: 4) {
                ForEach(
                    Array(TodoDateSupport.weekdaySymbols(locale: model.locale).enumerated()),
                    id: \.offset
                ) { index, symbol in
                    Text(symbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(
                            TodoDateSupport.isWeekendColumn(index)
                                ? Color.red.opacity(0.58)
                                : Color.secondary
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 4)
                }

                ForEach(TodoDateSupport.monthSlots(for: visibleMonth)) { slot in
                    if let day = slot.day {
                        CalendarDayCell(
                            day: day,
                            isSelected: day == selectedDay,
                            isToday: day == TodoDateSupport.localDay(from: .now),
                            occurrences: model.occurrences(on: day)
                        ) {
                            selectedDay = day
                        }
                    } else {
                        Color.clear
                            .frame(minHeight: 64)
                    }
                }
            }
        }
        .padding(20)
    }

    private var selectedOccurrences: [TodoOccurrence] {
        model.occurrences(on: selectedDay)
            .sorted {
                if $0.isCompleted != $1.isCompleted {
                    return !$0.isCompleted
                }
                if $0.isSkipped != $1.isSkipped {
                    return !$0.isSkipped
                }
                return TodoDateSupport.occurrenceTimeAscending($0, $1)
            }
    }

    private var selectedDayList: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(TodoDateSupport.longDate(selectedDay, locale: model.locale))
                        .font(.headline)
                    Text(selectedOccurrences.count, format: .number)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.openNewTodo(for: selectedDay)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(model.text("todos.new"))
            }
            .padding(16)

            Divider()

            if selectedOccurrences.isEmpty {
                ContentUnavailableView {
                    Label(
                        model.text("todos.calendar.empty.title"),
                        systemImage: "calendar.badge.plus"
                    )
                } description: {
                    Text(model.text("todos.calendar.empty.body"))
                } actions: {
                    Button(model.text("todos.new")) {
                        model.openNewTodo(for: selectedDay)
                    }
                }
            } else {
                List(selectedOccurrences) { occurrence in
                    TodoOccurrenceRow(model: model, occurrence: occurrence)
                }
                .listStyle(.inset)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    private func changeMonth(by value: Int) {
        guard let next = Calendar.current.date(
            byAdding: .month,
            value: value,
            to: visibleMonth
        ) else {
            return
        }
        let start = TodoDateSupport.startOfMonth(containing: next)
        visibleMonth = start
        selectedDay = TodoDateSupport.localDay(from: start)
    }
}

private struct CalendarDayCell: View {
    let day: LocalDay
    let isSelected: Bool
    let isToday: Bool
    let occurrences: [TodoOccurrence]
    let select: () -> Void
    @State private var isHovering = false

    private var openCount: Int {
        occurrences.filter { !$0.isCompleted && !$0.isSkipped }.count
    }

    private var allSettled: Bool {
        !occurrences.isEmpty && openCount == 0
    }

    private var isWeekend: Bool {
        TodoDateSupport.isWeekend(day)
    }

    private var visibleOccurrences: ArraySlice<TodoOccurrence> {
        occurrences.prefix(occurrences.count > 3 ? 2 : 3)
    }

    private var hiddenOccurrenceCount: Int {
        occurrences.count - visibleOccurrences.count
    }

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(day.day, format: .number)
                        .font(.callout.weight(isToday ? .bold : .regular))
                        .foregroundStyle(dayNumberColor)
                        .frame(width: 24, height: 24)
                        .overlay {
                            if isToday {
                                Circle()
                                    .stroke(Color.accentColor.opacity(0.72), lineWidth: 1.2)
                            }
                        }
                    Spacer(minLength: 0)
                    if !occurrences.isEmpty {
                        Text(occurrences.count, format: .number)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(allSettled ? Color.green : Color.accentColor)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(visibleOccurrences) { occurrence in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(dotColor(for: occurrence))
                                .frame(width: 5, height: 5)

                            Text(occurrence.title)
                                .font(.caption2)
                                .foregroundStyle(titleColor(for: occurrence))
                                .strikethrough(occurrence.isCompleted || occurrence.isSkipped)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Spacer(minLength: 0)
                        }
                    }

                    if hiddenOccurrenceCount > 0 {
                        Text("+\(hiddenOccurrenceCount)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .background(
                cellBackground,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        cellBorder,
                        lineWidth: isSelected ? 1.2 : (isToday ? 0.9 : 0.5)
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }

    private func dotColor(for occurrence: TodoOccurrence) -> Color {
        if occurrence.isSkipped { return .secondary.opacity(0.5) }
        if occurrence.isCompleted { return .green }
        return .accentColor
    }

    private func titleColor(for occurrence: TodoOccurrence) -> Color {
        if occurrence.isSkipped { return .secondary.opacity(0.65) }
        if occurrence.isCompleted { return .secondary }
        return .primary
    }

    private var dayNumberColor: Color {
        if isToday { return .accentColor }
        if isWeekend { return .red.opacity(0.62) }
        return .primary
    }

    private var cellBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.14) }
        if isToday { return Color.accentColor.opacity(0.07) }
        if isHovering { return Color.primary.opacity(0.035) }
        if isWeekend { return Color.red.opacity(0.035) }
        return .clear
    }

    private var cellBorder: Color {
        if isSelected { return Color.accentColor.opacity(0.7) }
        if isToday { return Color.accentColor.opacity(0.42) }
        if isHovering { return Color(nsColor: .separatorColor).opacity(0.8) }
        return Color(nsColor: .separatorColor).opacity(0.45)
    }
}

private struct TodoOccurrenceRow: View {
    @ObservedObject var model: AppModel
    let occurrence: TodoOccurrence
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                guard canToggle else { return }
                withAnimation(.snappy) {
                    model.toggle(occurrence)
                }
            } label: {
                Image(systemName: stateSymbol)
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(stateColor)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: occurrence.isCompleted)
            }
            .buttonStyle(HoverIconButtonStyle(kind: .accent))
            .disabled(!canToggle)
            .help(toggleHelp)

            VStack(alignment: .leading, spacing: 3) {
                Text(occurrence.title)
                    .foregroundStyle(occurrence.isCompleted || occurrence.isSkipped ? .secondary : .primary)
                    .strikethrough(occurrence.isCompleted)
                    .lineLimit(2)

                if !metadata.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(metadata, id: \.text) { item in
                            Label(item.text, systemImage: item.symbol)
                                .foregroundStyle(item.color)
                        }
                    }
                    .font(.caption)
                    .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 3) {
                Button {
                    model.edit(occurrence)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(HoverIconButtonStyle())
                .help(model.text("common.edit"))

                Button(role: .destructive) {
                    model.delete(occurrence)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(HoverIconButtonStyle(kind: .destructive))
                .help(model.text("todos.delete"))
            }
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(
                    model.highlightedTodoOccurrenceID == occurrence.id
                        ? Color.accentColor.opacity(0.14)
                        : isHovering
                            ? Color.primary.opacity(0.035)
                            : Color.clear
                )
        )
        .onTapGesture(count: 2) {
            model.edit(occurrence)
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            if canToggle {
                Button {
                    model.toggle(occurrence)
                } label: {
                    Label(toggleHelp, systemImage: stateSymbol)
                }
            }
            Button {
                model.edit(occurrence)
            } label: {
                Label(model.text("common.edit"), systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                model.delete(occurrence)
            } label: {
                Label(model.text("todos.delete"), systemImage: "trash")
            }
        }
        .task(id: model.highlightedTodoOccurrenceID) {
            guard model.highlightedTodoOccurrenceID == occurrence.id else {
                return
            }
            try? await Task.sleep(for: .seconds(3))
            if model.highlightedTodoOccurrenceID == occurrence.id {
                withAnimation(.easeOut(duration: 0.2)) {
                    model.highlightedTodoOccurrenceID = nil
                }
            }
        }
    }

    private var stateSymbol: String {
        if occurrence.isSkipped { return "forward.circle.fill" }
        return occurrence.isCompleted ? "checkmark.circle.fill" : "circle"
    }

    private var stateColor: Color {
        if occurrence.isSkipped { return .secondary }
        return occurrence.isCompleted ? .green : .accentColor
    }

    private var toggleHelp: String {
        if occurrence.isSkipped || isSettledRecurringHistory {
            return model.text("todos.state.history")
        }
        return occurrence.isCompleted
            ? model.text("todos.markOpen")
            : model.text("todos.markCompleted")
    }

    private var canToggle: Bool {
        !occurrence.isSkipped && !isSettledRecurringHistory
    }

    private var isSettledRecurringHistory: Bool {
        guard occurrence.isRecurring,
              let todo = model.todos.first(where: {
                  $0.id == occurrence.todoID
              }), let anchor = todo.scheduledDay else {
            return false
        }
        let today = TodoDateSupport.localDay(from: .now)
        let latestDue = todo.occurrences(from: anchor, through: today).last
        return latestDue?.id != occurrence.id
    }

    private var metadata: [TodoMetadataItem] {
        var result: [TodoMetadataItem] = []
        if let day = occurrence.scheduledDay {
            let overdue = TodoDateSupport.compare(
                day,
                TodoDateSupport.localDay(from: .now)
            ) == .orderedAscending && !occurrence.isCompleted && !occurrence.isSkipped
            result.append(
                TodoMetadataItem(
                    text: TodoDateSupport.shortDate(day, locale: model.locale),
                    symbol: overdue ? "exclamationmark.circle" : "calendar",
                    color: overdue ? .red : .secondary
                )
            )
        }
        if let time = occurrence.startTime {
            result.append(
                TodoMetadataItem(
                    text: TodoDateSupport.time(time, locale: model.locale),
                    symbol: "clock",
                    color: .secondary
                )
            )
        }
        if occurrence.isRecurring {
            result.append(
                TodoMetadataItem(
                    text: model.text("todos.recurrence.monthly.short"),
                    symbol: "repeat",
                    color: .orange
                )
            )
        }
        if occurrence.isSkipped {
            result.append(
                TodoMetadataItem(
                    text: model.text("todos.state.skipped"),
                    symbol: "forward.circle",
                    color: .secondary
                )
            )
        }
        return result
    }
}

private struct TodoMetadataItem {
    let text: String
    let symbol: String
    let color: Color
}

struct TodoEditorView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TodoEditorDraft
    @State private var saving = false

    init(model: AppModel, initialDraft: TodoEditorDraft) {
        self.model = model
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField(
                    model.text("todos.editor.title"),
                    text: $draft.title,
                    prompt: Text(model.text("todos.editor.title.placeholder"))
                )
                .textFieldStyle(.roundedBorder)

                Toggle(model.text("todos.editor.scheduled"), isOn: scheduledBinding)
                    .disabled(draft.editingOccurrenceID?.year != nil)

                if draft.scheduledDay != nil {
                    DatePicker(
                        model.text("todos.editor.date"),
                        selection: scheduledDateBinding,
                        displayedComponents: .date
                    )

                    Toggle(model.text("todos.editor.startTime"), isOn: startTimeBinding)

                    if draft.startTime != nil {
                        DatePicker(
                            model.text("todos.editor.startTime.value"),
                            selection: startTimeDateBinding,
                            displayedComponents: .hourAndMinute
                        )
                    }

                    Picker(model.text("todos.editor.recurrence"), selection: $draft.recurrence) {
                        Text(model.text("todos.recurrence.none"))
                            .tag(TodoRecurrence.none)
                        Text(model.text("todos.recurrence.monthly"))
                            .tag(TodoRecurrence.monthly)
                    }
                    .disabled(
                        draft.editingOccurrenceID?.year != nil
                            && draft.editScope == .onlyThis
                    )

                    if draft.editingOccurrenceID?.year != nil {
                        Picker(model.text("todos.editor.editScope"), selection: $draft.editScope) {
                            Text(model.text("todos.editScope.onlyThis"))
                                .tag(TodoEditScope.onlyThis)
                            Text(model.text("todos.editScope.thisAndFuture"))
                                .tag(TodoEditScope.thisAndFuture)
                        }
                    }

                    Toggle(
                        model.text("todos.editor.notification"),
                        isOn: notificationBinding
                    )

                    if draft.notificationEnabled {
                        DatePicker(
                            model.text("todos.editor.notificationTime"),
                            selection: notificationTimeDateBinding,
                            displayedComponents: .hourAndMinute
                        )
                    }

                    Toggle(
                        model.text("todos.editor.followUp"),
                        isOn: $draft.completionFollowUpEnabled
                    )
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button(model.text("common.cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(
                    draft.isEditing
                        ? model.text("common.save")
                        : model.text("common.create")
                ) {
                    saving = true
                    Task {
                        await model.saveTodo(draft)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!draft.isValid || saving)
            }
            .padding(16)
        }
        .frame(width: 500, height: draft.scheduledDay == nil ? 260 : 540)
        .navigationTitle(
            draft.isEditing
                ? model.text("todos.editor.edit")
                : model.text("todos.editor.new")
        )
        .onChange(of: draft.recurrence) { oldValue, newValue in
            if oldValue != .monthly && newValue == .monthly {
                draft.completionFollowUpEnabled = true
            }
        }
        .onChange(of: draft.startTime) { _, newValue in
            if let newValue, draft.notificationEnabled {
                draft.notificationTime = newValue
            }
        }
    }

    private var scheduledBinding: Binding<Bool> {
        Binding(
            get: { draft.scheduledDay != nil },
            set: { enabled in
                if enabled {
                    draft.scheduledDay = TodoDateSupport.localDay(from: .now)
                } else {
                    draft.scheduledDay = nil
                    draft.startTime = nil
                    draft.recurrence = .none
                    draft.notificationEnabled = false
                    draft.notificationTime = nil
                    draft.completionFollowUpEnabled = false
                }
            }
        )
    }

    private var scheduledDateBinding: Binding<Date> {
        Binding(
            get: {
                TodoDateSupport.date(
                    from: draft.scheduledDay ?? TodoDateSupport.localDay(from: .now)
                )
            },
            set: { draft.scheduledDay = TodoDateSupport.localDay(from: $0) }
        )
    }

    private var startTimeBinding: Binding<Bool> {
        Binding(
            get: { draft.startTime != nil },
            set: { enabled in
                if enabled {
                    let defaultTime = LocalTime(hour: 9, minute: 0)
                    draft.startTime = defaultTime
                    draft.notificationEnabled = true
                    draft.notificationTime = defaultTime
                } else {
                    draft.startTime = nil
                    draft.notificationEnabled = false
                    draft.notificationTime = nil
                }
            }
        )
    }

    private var startTimeDateBinding: Binding<Date> {
        Binding(
            get: { TodoDateSupport.date(from: draft.startTime ?? LocalTime(hour: 9, minute: 0)) },
            set: { draft.startTime = TodoDateSupport.localTime(from: $0) }
        )
    }

    private var notificationBinding: Binding<Bool> {
        Binding(
            get: { draft.notificationEnabled },
            set: { enabled in
                draft.notificationEnabled = enabled
                if enabled {
                    draft.notificationTime = draft.startTime ?? LocalTime(hour: 9, minute: 0)
                } else {
                    draft.notificationTime = nil
                }
            }
        )
    }

    private var notificationTimeDateBinding: Binding<Date> {
        Binding(
            get: {
                TodoDateSupport.date(
                    from: draft.notificationTime ?? draft.startTime ?? LocalTime(hour: 9, minute: 0)
                )
            },
            set: { draft.notificationTime = TodoDateSupport.localTime(from: $0) }
        )
    }
}

private enum TodoDateSupport {
    struct MonthSlot: Identifiable {
        let id: Int
        let day: LocalDay?
    }

    static func localDay(from date: Date, calendar: Calendar = .current) -> LocalDay {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return LocalDay(
            year: components.year ?? 1970,
            month: components.month ?? 1,
            day: components.day ?? 1
        )
    }

    static func date(from day: LocalDay, calendar: Calendar = .current) -> Date {
        calendar.date(
            from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)
        ) ?? .now
    }

    static func localTime(from date: Date, calendar: Calendar = .current) -> LocalTime {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return LocalTime(hour: components.hour ?? 9, minute: components.minute ?? 0)
    }

    static func date(from time: LocalTime, calendar: Calendar = .current) -> Date {
        calendar.date(
            from: DateComponents(year: 2001, month: 1, day: 1, hour: time.hour, minute: time.minute)
        ) ?? .now
    }

    static func compare(_ lhs: LocalDay, _ rhs: LocalDay) -> ComparisonResult {
        if lhs.year != rhs.year {
            return lhs.year < rhs.year ? .orderedAscending : .orderedDescending
        }
        if lhs.month != rhs.month {
            return lhs.month < rhs.month ? .orderedAscending : .orderedDescending
        }
        if lhs.day != rhs.day {
            return lhs.day < rhs.day ? .orderedAscending : .orderedDescending
        }
        return .orderedSame
    }

    static func startOfMonth(containing date: Date, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    static func monthSlots(for month: Date, calendar: Calendar = .current) -> [MonthSlot] {
        let monthStart = startOfMonth(containing: month, calendar: calendar)
        guard let dayRange = calendar.range(of: .day, in: .month, for: monthStart) else {
            return []
        }
        let weekday = calendar.component(.weekday, from: monthStart)
        let leadingCount = (weekday - calendar.firstWeekday + 7) % 7
        var slots = (0..<leadingCount).map { MonthSlot(id: $0, day: nil) }
        let startID = slots.count
        slots.append(contentsOf: dayRange.compactMap { day -> MonthSlot? in
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else {
                return nil
            }
            return MonthSlot(id: startID + day - 1, day: localDay(from: date, calendar: calendar))
        })
        return slots
    }

    static func weekdaySymbols(locale: Locale) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = locale
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? []
        guard symbols.count == 7 else { return symbols }
        let offset = Calendar.current.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    static func isWeekendColumn(_ index: Int, calendar: Calendar = .current) -> Bool {
        let weekday = ((calendar.firstWeekday - 1 + index) % 7) + 1
        return weekday == 1 || weekday == 7
    }

    static func isWeekend(_ day: LocalDay, calendar: Calendar = .current) -> Bool {
        calendar.isDateInWeekend(date(from: day, calendar: calendar))
    }

    static func monthTitle(_ date: Date, locale: Locale) -> String {
        formatter(locale: locale, template: "yMMMM").string(from: date)
    }

    static func shortDate(_ day: LocalDay, locale: Locale) -> String {
        formatter(locale: locale, template: "MMMd").string(from: date(from: day))
    }

    static func longDate(_ day: LocalDay, locale: Locale) -> String {
        formatter(locale: locale, template: "yMMMMEEEEd").string(from: date(from: day))
    }

    static func time(_ time: LocalTime, locale: Locale) -> String {
        formatter(locale: locale, template: "jmm").string(from: date(from: time))
    }

    static func occurrenceTimeAscending(_ lhs: TodoOccurrence, _ rhs: TodoOccurrence) -> Bool {
        switch (lhs.startTime, rhs.startTime) {
        case let (left?, right?):
            if left.hour != right.hour { return left.hour < right.hour }
            if left.minute != right.minute { return left.minute < right.minute }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        case (nil, _?):
            return true
        case (_?, nil):
            return false
        case (nil, nil):
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    static func occurrenceDayAscending(_ lhs: TodoOccurrence, _ rhs: TodoOccurrence) -> Bool {
        switch (lhs.scheduledDay, rhs.scheduledDay) {
        case let (left?, right?):
            let result = compare(left, right)
            if result != .orderedSame { return result == .orderedAscending }
            return occurrenceTimeAscending(lhs, rhs)
        case (nil, _?):
            return true
        case (_?, nil):
            return false
        case (nil, nil):
            return occurrenceTimeAscending(lhs, rhs)
        }
    }

    private static func formatter(locale: Locale, template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}
