import SwiftUI

struct ReminderWorkspace: View {
    @ObservedObject var model: AppModel
    @State private var selectedID: String?

    private var active: [ReminderRecord] {
        model.reminders.filter(\.isEnabled)
    }

    private var paused: [ReminderRecord] {
        model.reminders.filter { !$0.isEnabled && $0.completedAt == nil }
    }

    private var completed: [ReminderRecord] {
        model.reminders.filter { $0.completedAt != nil }
    }

    var body: some View {
        Group {
            if model.reminders.isEmpty {
                ContentUnavailableView {
                    Label(
                        model.text("reminders.empty.title"),
                        systemImage: "checkmark.circle"
                    )
                } description: {
                    Text(model.text("reminders.empty.body"))
                } actions: {
                    Button(model.text("reminders.new")) {
                        model.openNewReminder()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List(selection: $selectedID) {
                    reminderSection(
                        title: model.text("reminders.active"),
                        reminders: active
                    )
                    reminderSection(
                        title: model.text("reminders.paused"),
                        reminders: paused
                    )
                    reminderSection(
                        title: model.text("reminders.completed"),
                        reminders: completed
                    )
                }
                .listStyle(.inset)
                .onDeleteCommand {
                    guard
                        let selectedID,
                        let reminder = model.reminders.first(where: { $0.id == selectedID })
                    else {
                        return
                    }
                    model.requestDelete(reminder)
                }
            }
        }
        .navigationTitle(model.text("reminders.title"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.openNewReminder()
                } label: {
                    Label(model.text("reminders.new"), systemImage: "plus")
                }
                .help(model.text("reminders.new"))
            }
        }
    }

    @ViewBuilder
    private func reminderSection(
        title: String,
        reminders: [ReminderRecord]
    ) -> some View {
        if !reminders.isEmpty {
            Section {
                ForEach(reminders) { reminder in
                    ReminderRow(model: model, reminder: reminder)
                        .tag(reminder.id)
                }
            } header: {
                HStack {
                    Text(title)
                    Spacer()
                    Text(reminders.count, format: .number)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
        }
    }
}

private struct ReminderRow: View {
    @ObservedObject var model: AppModel
    let reminder: ReminderRecord
    @State private var previewing = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                model.toggle(reminder)
            } label: {
                Image(
                    systemName: reminder.completedAt != nil
                        ? "checkmark.circle.fill"
                        : reminder.isEnabled
                            ? "pause.circle.fill"
                            : "play.circle"
                )
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(reminder.isEnabled ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(
                reminder.isEnabled
                    ? model.text("reminders.pause")
                    : model.text("reminders.resume")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.content)
                    .fontWeight(.medium)
                    .foregroundStyle(
                        reminder.isEnabled ? .primary : .secondary
                    )
                    .lineLimit(1)

                HStack(spacing: 12) {
                    Label(
                        intervalLabel,
                        systemImage: reminder.repeats ? "repeat" : "1.circle"
                    )
                    if let next = reminder.nextTriggerAt {
                        Text(
                            "\(model.text("reminders.next")) \(next.formatted(date: .omitted, time: .standard))"
                        )
                        .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(action: preview) {
                if previewing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "bell.badge")
                }
            }
            .buttonStyle(.plain)
            .help(model.text("reminders.try.help"))
            .disabled(previewing)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 5)
        .onTapGesture(count: 2) {
            model.edit(reminder)
        }
        .contextMenu {
            Button {
                model.toggle(reminder)
            } label: {
                Label(
                    reminder.isEnabled
                        ? model.text("reminders.pause")
                        : model.text("reminders.resume"),
                    systemImage: reminder.isEnabled ? "pause" : "play"
                )
            }
            Button {
                model.edit(reminder)
            } label: {
                Label(model.text("reminders.edit"), systemImage: "pencil")
            }
            Button(action: preview) {
                Label(
                    model.text("reminders.try"),
                    systemImage: "bell.badge"
                )
            }
            Divider()
            Button(role: .destructive) {
                model.requestDelete(reminder)
            } label: {
                Label(model.text("reminders.delete"), systemImage: "trash")
            }
        }
    }

    private var intervalLabel: String {
        let value = Duration.seconds(reminder.intervalSeconds)
            .formatted(
                .units(
                    allowed: [.hours, .minutes, .seconds],
                    width: .abbreviated,
                    maximumUnitCount: 3
                )
            )
        return reminder.repeats
            ? "\(model.text("reminders.every")) \(value)"
            : "\(model.text("reminders.once")) · \(value)"
    }

    private func preview() {
        guard !previewing else { return }
        previewing = true
        Task {
            _ = await model.previewReminder(content: reminder.content)
            previewing = false
        }
    }
}

struct ReminderEditorView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ReminderDraft
    @State private var saving = false
    @State private var previewing = false
    @State private var previewFailed = false

    init(model: AppModel, initialDraft: ReminderDraft) {
        self.model = model
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField(
                    model.text("editor.content"),
                    text: $draft.content,
                    prompt: Text(model.text("editor.content.placeholder"))
                )
                .textFieldStyle(.roundedBorder)

                LabeledContent(model.text("editor.interval")) {
                    HStack(spacing: 14) {
                        DurationStepper(
                            label: model.text("editor.hours"),
                            value: $draft.hours,
                            range: 0...23
                        )
                        DurationStepper(
                            label: model.text("editor.minutes"),
                            value: $draft.minutes,
                            range: 0...59
                        )
                        DurationStepper(
                            label: model.text("editor.seconds"),
                            value: $draft.seconds,
                            range: 0...59
                        )
                    }
                }

                Picker(model.text("editor.mode"), selection: $draft.repeats) {
                    Text(model.text("reminders.repeat")).tag(true)
                    Text(model.text("reminders.once")).tag(false)
                }
                .pickerStyle(.segmented)

                Toggle(model.text("editor.enabled"), isOn: $draft.isEnabled)
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button {
                    previewing = true
                    Task {
                        let delivered = await model.previewReminder(
                            content: draft.content
                        )
                        previewing = false
                        previewFailed = !delivered
                    }
                } label: {
                    if previewing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(
                            model.text("reminders.try"),
                            systemImage: "bell.badge"
                        )
                    }
                }
                .buttonStyle(.bordered)
                .disabled(
                    draft.content
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty || previewing
                )
                .help(model.text("reminders.try.help"))

                Spacer()
                Button(model.text("common.cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(
                    draft.editingID == nil
                        ? model.text("common.create")
                        : model.text("common.save")
                ) {
                    saving = true
                    Task {
                        await model.saveReminder(draft)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!draft.isValid || saving)
            }
            .padding(16)
        }
        .frame(width: 500, height: 330)
        .navigationTitle(
            draft.editingID == nil
                ? model.text("editor.new")
                : model.text("editor.edit")
        )
        .alert(
            model.text("reminders.try.failed"),
            isPresented: $previewFailed
        ) {
            Button(model.text("common.close"), role: .cancel) {}
        } message: {
            Text(
                model.text(
                    model.notificationState == .denied
                        ? "status.permissionDenied"
                        : "reminders.try.failed.body"
                )
            )
        }
    }
}

private struct DurationStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Stepper(value: $value, in: range) {
                Text(value, format: .number)
                    .frame(minWidth: 24, alignment: .trailing)
                    .monospacedDigit()
            }
        }
    }
}
