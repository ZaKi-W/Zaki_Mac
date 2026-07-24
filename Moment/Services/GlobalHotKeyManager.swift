import AppKit
import Carbon.HIToolbox
import Foundation

@MainActor
protocol GlobalShortcutManaging: AnyObject {
    func register(shortcut: String, handler: @escaping @MainActor () -> Void) -> Bool
    func unregister()
}

struct ShortcutDefinition: Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32
    var displayValue: String
    var storageValue: String
}

enum ShortcutParser {
    static func parse(_ value: String) -> ShortcutDefinition? {
        let parts = value.split(separator: "+").map(String.init)
        guard let key = parts.last else { return nil }
        var modifiers: UInt32 = 0
        var display = ""
        var storage: [String] = []

        for modifier in parts.dropLast() {
            switch modifier.lowercased() {
            case "command", "commandorcontrol", "meta":
                modifiers |= UInt32(cmdKey)
                display += "⌘"
                storage.append("Command")
            case "shift":
                modifiers |= UInt32(shiftKey)
                display += "⇧"
                storage.append("Shift")
            case "option", "alt":
                modifiers |= UInt32(optionKey)
                display += "⌥"
                storage.append("Option")
            case "control", "ctrl":
                modifiers |= UInt32(controlKey)
                display += "⌃"
                storage.append("Control")
            default:
                continue
            }
        }

        guard modifiers != 0, let keyCode = keyCode(for: key) else {
            return nil
        }
        let normalizedKey = key.uppercased()
        display += displayKey(normalizedKey)
        storage.append(normalizedKey)
        return ShortcutDefinition(
            keyCode: keyCode,
            modifiers: modifiers,
            displayValue: display,
            storageValue: storage.joined(separator: "+")
        )
    }

    static func from(event: NSEvent) -> ShortcutDefinition? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var storage: [String] = []
        var display = ""
        var carbonModifiers: UInt32 = 0

        if flags.contains(.command) {
            storage.append("Command")
            display += "⌘"
            carbonModifiers |= UInt32(cmdKey)
        }
        if flags.contains(.shift) {
            storage.append("Shift")
            display += "⇧"
            carbonModifiers |= UInt32(shiftKey)
        }
        if flags.contains(.option) {
            storage.append("Option")
            display += "⌥"
            carbonModifiers |= UInt32(optionKey)
        }
        if flags.contains(.control) {
            storage.append("Control")
            display += "⌃"
            carbonModifiers |= UInt32(controlKey)
        }
        guard carbonModifiers != 0 else { return nil }

        let keyName = keyName(for: event.keyCode)
        guard !keyName.isEmpty else { return nil }
        storage.append(keyName)
        display += displayKey(keyName)
        return ShortcutDefinition(
            keyCode: UInt32(event.keyCode),
            modifiers: carbonModifiers,
            displayValue: display,
            storageValue: storage.joined(separator: "+")
        )
    }

    private static func keyCode(for key: String) -> UInt32? {
        let map: [String: Int] = [
            "A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C,
            "D": kVK_ANSI_D, "E": kVK_ANSI_E, "F": kVK_ANSI_F,
            "G": kVK_ANSI_G, "H": kVK_ANSI_H, "I": kVK_ANSI_I,
            "J": kVK_ANSI_J, "K": kVK_ANSI_K, "L": kVK_ANSI_L,
            "M": kVK_ANSI_M, "N": kVK_ANSI_N, "O": kVK_ANSI_O,
            "P": kVK_ANSI_P, "Q": kVK_ANSI_Q, "R": kVK_ANSI_R,
            "S": kVK_ANSI_S, "T": kVK_ANSI_T, "U": kVK_ANSI_U,
            "V": kVK_ANSI_V, "W": kVK_ANSI_W, "X": kVK_ANSI_X,
            "Y": kVK_ANSI_Y, "Z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2,
            "3": kVK_ANSI_3, "4": kVK_ANSI_4, "5": kVK_ANSI_5,
            "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8,
            "9": kVK_ANSI_9, "SPACE": kVK_Space,
            "LEFT": kVK_LeftArrow, "RIGHT": kVK_RightArrow,
            "UP": kVK_UpArrow, "DOWN": kVK_DownArrow
        ]
        return map[key.uppercased()].map(UInt32.init)
    }

    private static func keyName(for keyCode: UInt16) -> String {
        let map: [UInt16: String] = [
            UInt16(kVK_ANSI_A): "A", UInt16(kVK_ANSI_B): "B",
            UInt16(kVK_ANSI_C): "C", UInt16(kVK_ANSI_D): "D",
            UInt16(kVK_ANSI_E): "E", UInt16(kVK_ANSI_F): "F",
            UInt16(kVK_ANSI_G): "G", UInt16(kVK_ANSI_H): "H",
            UInt16(kVK_ANSI_I): "I", UInt16(kVK_ANSI_J): "J",
            UInt16(kVK_ANSI_K): "K", UInt16(kVK_ANSI_L): "L",
            UInt16(kVK_ANSI_M): "M", UInt16(kVK_ANSI_N): "N",
            UInt16(kVK_ANSI_O): "O", UInt16(kVK_ANSI_P): "P",
            UInt16(kVK_ANSI_Q): "Q", UInt16(kVK_ANSI_R): "R",
            UInt16(kVK_ANSI_S): "S", UInt16(kVK_ANSI_T): "T",
            UInt16(kVK_ANSI_U): "U", UInt16(kVK_ANSI_V): "V",
            UInt16(kVK_ANSI_W): "W", UInt16(kVK_ANSI_X): "X",
            UInt16(kVK_ANSI_Y): "Y", UInt16(kVK_ANSI_Z): "Z",
            UInt16(kVK_ANSI_0): "0", UInt16(kVK_ANSI_1): "1",
            UInt16(kVK_ANSI_2): "2", UInt16(kVK_ANSI_3): "3",
            UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5",
            UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7",
            UInt16(kVK_ANSI_8): "8", UInt16(kVK_ANSI_9): "9",
            UInt16(kVK_Space): "SPACE", UInt16(kVK_LeftArrow): "LEFT",
            UInt16(kVK_RightArrow): "RIGHT", UInt16(kVK_UpArrow): "UP",
            UInt16(kVK_DownArrow): "DOWN"
        ]
        return map[keyCode] ?? ""
    }

    private static func displayKey(_ key: String) -> String {
        switch key {
        case "SPACE": "Space"
        case "LEFT": "←"
        case "RIGHT": "→"
        case "UP": "↑"
        case "DOWN": "↓"
        default: key
        }
    }
}

@MainActor
final class GlobalHotKeyManager: GlobalShortcutManaging {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var action: (@MainActor () -> Void)?

    init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, pointer in
                guard let pointer else { return noErr }
                let manager = Unmanaged<GlobalHotKeyManager>
                    .fromOpaque(pointer)
                    .takeUnretainedValue()
                Task { @MainActor in
                    manager.action?()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    func register(
        shortcut: String,
        handler: @escaping @MainActor () -> Void
    ) -> Bool {
        unregister()
        guard let definition = ShortcutParser.parse(shortcut) else {
            return false
        }
        let identifier = EventHotKeyID(signature: 0x4D4F4D54, id: 1)
        let status = RegisterEventHotKey(
            definition.keyCode,
            definition.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard status == noErr else {
            hotKey = nil
            return false
        }
        action = handler
        return true
    }

    func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        hotKey = nil
        action = nil
    }
}
