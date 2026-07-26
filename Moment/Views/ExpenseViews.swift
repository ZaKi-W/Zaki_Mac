import SwiftUI

struct ExpenseWorkspace: View {
    @ObservedObject var model: AppModel
    @State private var editorExpense: RecurringExpense?
    @State private var isShowingEditor = false

    private var expenses: [RecurringExpense] {
        model.life.recurringExpenses
    }

    private var enabledExpenses: [RecurringExpense] {
        expenses.filter(\.isEnabled)
    }

    private var monthlyTotal: Decimal {
        enabledExpenses.reduce(0) { $0 + $1.monthlyEquivalent }
    }

    private var annualTotal: Decimal {
        enabledExpenses.reduce(0) { $0 + $1.annualEquivalent }
    }

    private var dueWithin30Days: Decimal {
        let end = Calendar.current.date(byAdding: .day, value: 30, to: .now)!
        return enabledExpenses.reduce(0) {
            $0 + $1.amountDue(from: .now, through: end)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    LifeSummarySection(
                        title: model.text("expenses.summary"),
                        systemImage: "gauge.with.dots.needle.67percent"
                    ) {
                        LifeCardGrid {
                            LifeMetricCard(
                                title: model.text("expenses.monthly"),
                                value: LifeFormat.currency(monthlyTotal),
                                detail: model.text("expenses.monthly.detail"),
                                systemImage: "calendar",
                                tint: .blue
                            )
                            LifeMetricCard(
                                title: model.text("expenses.annual"),
                                value: LifeFormat.currency(annualTotal),
                                detail: model.text("expenses.annual.detail"),
                                systemImage: "calendar.badge.clock",
                                tint: .green
                            )
                            LifeMetricCard(
                                title: model.text("expenses.next30Days"),
                                value: LifeFormat.currency(dueWithin30Days),
                                detail: model.text("expenses.next30Days.detail"),
                                systemImage: "creditcard.fill",
                                tint: dueWithin30Days > 0 ? .orange : .secondary
                            )
                        }
                    }

                    if expenses.isEmpty {
                        LifeEmptyCard(
                            title: model.text("expenses.empty.title"),
                            message: model.text("expenses.empty.body"),
                            systemImage: "repeat.circle",
                            buttonTitle: model.text("expenses.add")
                        ) {
                            editorExpense = nil
                            isShowingEditor = true
                        }
                    } else {
                        LifeSectionHeader(
                            title: model.text("expenses.items"),
                            detail: "\(expenses.count)",
                            systemImage: "creditcard",
                            showsDivider: true
                        )

                        LifeCardGrid {
                            ForEach(sortedExpenses) { expense in
                                RecurringExpenseCard(
                                    model: model,
                                    expense: expense,
                                    isHighlighted: model.highlightedExpenseID == expense.id,
                                    edit: {
                                        editorExpense = expense
                                        isShowingEditor = true
                                    },
                                    archive: {
                                        model.archiveRecurringExpense(expense)
                                    }
                                )
                                .id(expense.id)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .onAppear {
                scrollToHighlighted(using: proxy)
            }
            .onChange(of: model.highlightedExpenseID) {
                scrollToHighlighted(using: proxy)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(model.text("expenses.title"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editorExpense = nil
                    isShowingEditor = true
                } label: {
                    Label(model.text("expenses.add"), systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            RecurringExpenseEditorView(model: model, expense: editorExpense)
        }
    }

    private var sortedExpenses: [RecurringExpense] {
        expenses.sorted {
            let left = $0.nextDueDate(onOrAfter: .now) ?? .distantFuture
            let right = $1.nextDueDate(onOrAfter: .now) ?? .distantFuture
            if left == right {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return left < right
        }
    }

    private func scrollToHighlighted(using proxy: ScrollViewProxy) {
        guard let id = model.highlightedExpenseID else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(id, anchor: .center)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if model.highlightedExpenseID == id {
                model.highlightedExpenseID = nil
            }
        }
    }
}

private struct RecurringExpenseCard: View {
    @ObservedObject var model: AppModel
    let expense: RecurringExpense
    let isHighlighted: Bool
    let edit: () -> Void
    let archive: () -> Void

    private var nextDue: Date? {
        expense.nextDueDate(onOrAfter: .now)
    }

    private var remainingOccurrences: Int? {
        expense.remainingOccurrences(onOrAfter: .now)
    }

    var body: some View {
        LifeCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(expense.name)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    Spacer()
                    Menu {
                        Button(model.text("common.edit"), action: edit)
                        Divider()
                        Button(model.text("expenses.pause"), action: archive)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(LifeFormat.currency(expense.amount))
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                    Text(cycleLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    LifeStatusPill(
                        title: expense.isEnabled
                            ? model.text("expenses.status.active")
                            : model.text("expenses.status.paused"),
                        systemImage: expense.isEnabled ? "checkmark.circle.fill" : "pause.circle",
                        tint: expense.isEnabled ? .green : .secondary
                    )
                    if expense.autoRenews {
                        LifeStatusPill(
                            title: model.text("expenses.autoRenew"),
                            systemImage: "repeat",
                            tint: .blue
                        )
                    }
                    if isHighlighted {
                        LifeStatusPill(
                            title: model.text("expenses.status.upcoming"),
                            systemImage: "bell.fill",
                            tint: .orange
                        )
                    }
                }

                Divider()

                ExpenseMetadataRow(
                    title: model.text("expenses.nextDue"),
                    value: LifeFormat.date(nextDue)
                )
                ExpenseMetadataRow(
                    title: model.text("expenses.monthlyEquivalent"),
                    value: LifeFormat.currency(expense.monthlyEquivalent)
                )
                ExpenseMetadataRow(
                    title: model.text("expenses.remaining"),
                    value: remainingOccurrences.map(String.init)
                        ?? model.text("expenses.ongoing")
                )
                if expense.reminderEnabled {
                    ExpenseMetadataRow(
                        title: model.text("expenses.reminder"),
                        value: "\(expense.reminderLeadDays) \(model.text("common.daysBefore"))"
                    )
                }
            }
        }
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.orange, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
        .contextMenu {
            Button(model.text("common.edit"), action: edit)
            Divider()
            Button(model.text("expenses.pause"), action: archive)
        }
    }

    private var cycleLabel: String {
        let unit = model.text("expenses.cycle.\(expense.cycle.unit.rawValue)")
        return "\(expense.cycle.interval) \(unit)"
    }
}

private struct ExpenseMetadataRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.caption)
    }
}

private struct RecurringExpenseEditorView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let expense: RecurringExpense?

    @State private var name: String
    @State private var amount: Decimal
    @State private var cycleUnit: BillingCycleUnit
    @State private var cycleInterval: Int
    @State private var anchorDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var autoRenews: Bool
    @State private var reminderEnabled: Bool
    @State private var reminderLeadDays: Int
    @State private var isEnabled: Bool
    @State private var notes: String

    init(model: AppModel, expense: RecurringExpense?) {
        self.model = model
        self.expense = expense
        _name = State(initialValue: expense?.name ?? "")
        _amount = State(initialValue: expense?.amount ?? 0)
        _cycleUnit = State(initialValue: expense?.cycle.unit ?? .month)
        _cycleInterval = State(initialValue: expense?.cycle.interval ?? 1)
        _anchorDate = State(initialValue: expense?.anchorDate ?? .now)
        _hasEndDate = State(initialValue: expense?.endDate != nil)
        _endDate = State(initialValue: expense?.endDate ?? .now)
        _autoRenews = State(initialValue: expense?.autoRenews ?? true)
        _reminderEnabled = State(initialValue: expense?.reminderEnabled ?? true)
        _reminderLeadDays = State(initialValue: expense?.reminderLeadDays ?? 3)
        _isEnabled = State(initialValue: expense?.isEnabled ?? true)
        _notes = State(initialValue: expense?.notes ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(model.text("expenses.editor.details")) {
                    TextField(model.text("expenses.field.name"), text: $name)
                    TextField(
                        model.text("expenses.field.amount"),
                        value: $amount,
                        format: .number
                    )
                }

                Section(model.text("expenses.editor.schedule")) {
                    Picker(model.text("expenses.field.cycle"), selection: $cycleUnit) {
                        ForEach(BillingCycleUnit.allCases) { unit in
                            Text(model.text("expenses.cycle.\(unit.rawValue)")).tag(unit)
                        }
                    }
                    Stepper(
                        "\(model.text("expenses.field.interval")): \(cycleInterval)",
                        value: $cycleInterval,
                        in: 1...99
                    )
                    DatePicker(
                        model.text("expenses.field.anchorDate"),
                        selection: $anchorDate,
                        displayedComponents: .date
                    )
                    Toggle(model.text("expenses.field.endDate.enable"), isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker(
                            model.text("expenses.field.endDate"),
                            selection: $endDate,
                            in: anchorDate...,
                            displayedComponents: .date
                        )
                    }
                    Toggle(model.text("expenses.autoRenew"), isOn: $autoRenews)
                }

                Section(model.text("expenses.editor.reminder")) {
                    Toggle(model.text("expenses.reminder.enable"), isOn: $reminderEnabled)
                    if reminderEnabled {
                        Stepper(
                            "\(model.text("expenses.reminder.leadDays")): \(reminderLeadDays)",
                            value: $reminderLeadDays,
                            in: 0...90
                        )
                    }
                    Toggle(model.text("expenses.field.enabled"), isOn: $isEnabled)
                }

                Section(model.text("common.notes")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }
            }
            .formStyle(.grouped)

            Divider()

            LifeSheetFooter(
                cancelTitle: model.text("common.cancel"),
                saveTitle: expense == nil
                    ? model.text("common.create")
                    : model.text("common.save"),
                saveDisabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || amount < 0
                    || (hasEndDate && endDate < anchorDate),
                cancel: { dismiss() }
            ) {
                model.saveRecurringExpense(
                    RecurringExpense(
                        id: expense?.id ?? UUID().uuidString,
                        name: name,
                        amount: amount,
                        currency: "CNY",
                        cycle: BillingCycle(
                            unit: cycleUnit,
                            interval: cycleInterval
                        ),
                        anchorDate: anchorDate,
                        endDate: hasEndDate ? endDate : nil,
                        autoRenews: autoRenews,
                        reminderEnabled: reminderEnabled,
                        reminderLeadDays: reminderLeadDays,
                        isEnabled: isEnabled,
                        notes: notes,
                        createdAt: expense?.createdAt ?? .now
                    )
                )
                if reminderEnabled && isEnabled {
                    Task { await model.requestNotificationPermissionIfNeeded() }
                }
                dismiss()
            }
        }
        .frame(width: 560, height: 630)
    }
}
