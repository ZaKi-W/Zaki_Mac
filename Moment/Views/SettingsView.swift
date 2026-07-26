import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            GeneralSettings(model: model)
                .tabItem {
                    Label(model.text("settings.general"), systemImage: "gear")
                }
            LifeSettings(model: model)
                .tabItem {
                    Label(
                        model.text("settings.life"),
                        systemImage: "house"
                    )
                }
            ShortcutSettings(model: model)
                .tabItem {
                    Label(
                        model.text("settings.shortcuts"),
                        systemImage: "keyboard"
                    )
                }
            AboutSettings(model: model)
                .tabItem {
                    Label(model.text("settings.about"), systemImage: "info.circle")
                }
        }
        .frame(width: 540, height: 370)
        .padding(20)
    }
}

private struct GeneralSettings: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Picker(
                model.text("settings.appearance"),
                selection: Binding(
                    get: { model.preferences.appearance },
                    set: { model.updateAppearance($0) }
                )
            ) {
                Text(model.text("settings.system")).tag(AppearanceMode.system)
                Text(model.text("settings.light")).tag(AppearanceMode.light)
                Text(model.text("settings.dark")).tag(AppearanceMode.dark)
            }
            .pickerStyle(.segmented)

            Picker(
                model.text("settings.language"),
                selection: Binding(
                    get: { model.preferences.language },
                    set: { model.updateLanguage($0) }
                )
            ) {
                Text(model.text("settings.chinese")).tag(AppLanguage.zh)
                Text(model.text("settings.english")).tag(AppLanguage.en)
            }

            Toggle(
                model.text("settings.browserDark"),
                isOn: Binding(
                    get: { model.preferences.browserDarkMode },
                    set: { model.updateBrowserDarkMode($0) }
                )
            )

            LabeledContent(model.text("settings.notification")) {
                HStack {
                    Text(notificationLabel)
                        .foregroundStyle(
                            model.notificationState == .denied
                                ? Color.red
                                : Color.secondary
                        )
                    if model.notificationState == .denied {
                        Button(model.text("settings.openSystemSettings")) {
                            model.openNotificationSettings()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await model.refreshNotificationState()
        }
    }

    private var notificationLabel: String {
        switch model.notificationState {
        case .allowed:
            model.text("settings.notification.allowed")
        case .denied:
            model.text("settings.notification.denied")
        case .unknown:
            model.text("settings.notification.unknown")
        }
    }
}

private struct LifeSettings: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section(model.text("settings.inventoryReview")) {
                Toggle(
                    model.text("settings.inventoryReview.enabled"),
                    isOn: Binding(
                        get: { model.life.inventoryReviewSettings.isEnabled },
                        set: { enabled in
                            updateSchedule(isEnabled: enabled)
                            if enabled {
                                Task {
                                    await model.requestNotificationPermissionIfNeeded()
                                }
                            }
                        }
                    )
                )

                Picker(
                    model.text("settings.inventoryReview.weekday"),
                    selection: Binding(
                        get: { model.life.inventoryReviewSettings.weekday },
                        set: { updateSchedule(weekday: $0) }
                    )
                ) {
                    ForEach(1...7, id: \.self) { weekday in
                        Text(
                            Calendar.current.weekdaySymbols[
                                (weekday - 1)
                                % Calendar.current.weekdaySymbols.count
                            ]
                        )
                        .tag(weekday)
                    }
                }

                DatePicker(
                    model.text("settings.inventoryReview.time"),
                    selection: Binding(
                        get: {
                            let settings = model.life.inventoryReviewSettings
                            return Calendar.current.date(
                                bySettingHour: settings.hour,
                                minute: settings.minute,
                                second: 0,
                                of: .now
                            ) ?? .now
                        },
                        set: { date in
                            let components = Calendar.current.dateComponents(
                                [.hour, .minute],
                                from: date
                            )
                            updateSchedule(
                                hour: components.hour,
                                minute: components.minute
                            )
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )
            }

            Section(model.text("settings.backup")) {
                LabeledContent(model.text("settings.backup.description")) {
                    Button(model.text("settings.backup.export")) {
                        model.exportBackup()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func updateSchedule(
        weekday: Int? = nil,
        hour: Int? = nil,
        minute: Int? = nil,
        isEnabled: Bool? = nil
    ) {
        let current = model.life.inventoryReviewSettings
        model.updateInventoryReviewSchedule(
            weekday: weekday ?? current.weekday,
            hour: hour ?? current.hour,
            minute: minute ?? current.minute,
            isEnabled: isEnabled ?? current.isEnabled
        )
    }
}

private struct ShortcutSettings: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            LabeledContent(model.text("settings.globalShortcut")) {
                ShortcutRecorder(
                    shortcut: model.preferences.globalShortcut,
                    onChange: { model.updateGlobalShortcut($0) }
                )
                .frame(width: 150, height: 26)
            }
            Text(model.text("settings.shortcutHint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct AboutSettings: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
            Text(model.text("app.name"))
                .font(.title2.weight(.semibold))
            Text(
                "\(model.text("settings.version")) \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")"
            )
            .foregroundStyle(.secondary)
            Text("SwiftUI · AppKit · WebKit")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: String
    let onChange: (String) -> Void

    func makeNSView(context: Context) -> ShortcutTextField {
        let field = ShortcutTextField()
        field.onShortcut = onChange
        field.alignment = .center
        field.isEditable = false
        field.isSelectable = false
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.stringValue = ShortcutParser.parse(shortcut)?.displayValue ?? shortcut
        return field
    }

    func updateNSView(_ field: ShortcutTextField, context: Context) {
        field.onShortcut = onChange
        if field.currentEditor() == nil {
            field.stringValue = ShortcutParser.parse(shortcut)?.displayValue ?? shortcut
        }
    }
}

final class ShortcutTextField: NSTextField {
    var onShortcut: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        stringValue = "Type Shortcut"
    }

    override func keyDown(with event: NSEvent) {
        guard let definition = ShortcutParser.from(event: event) else {
            NSSound.beep()
            return
        }
        stringValue = definition.displayValue
        onShortcut?(definition.storageValue)
    }
}
