import AppKit
import SwiftUI

struct MainWindowBehavior: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.identifier = NSUserInterfaceItemIdentifier("moment.main")
            window.delegate = context.coordinator
            window.isReleasedWhenClosed = false
            window.titlebarSeparatorStyle = .automatic
            window.toolbarStyle = .unified
            window.minSize = NSSize(width: 760, height: 520)
            context.coordinator.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        private weak var window: NSWindow?
        private var keyMonitor: Any?

        func attach(to window: NSWindow) {
            self.window = window
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                [weak self] event in
                guard
                    let self,
                    event.window === self.window,
                    event.charactersIgnoringModifiers?.lowercased() == "w",
                    event.modifierFlags
                        .intersection(.deviceIndependentFlagsMask) == [.command]
                else {
                    return event
                }
                NotificationCenter.default.post(
                    name: .momentCloseCommand,
                    object: nil
                )
                return nil
            }
        }

        func detach() {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
            }
            keyMonitor = nil
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            sender.orderOut(nil)
            return false
        }
    }
}
