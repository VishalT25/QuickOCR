import AppKit
import ApplicationServices

final class HotkeyManager {
    static let shared = HotkeyManager()

    var onTrigger: (() -> Void)?
    private var monitor: Any?

    private init() {}

    func start() {
        if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
        }

        let relevant: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let sc    = PreferencesManager.shared.shortcut
            let flags = event.modifierFlags.intersection(relevant)
            guard event.keyCode == sc.keyCode, flags == sc.modifiers else { return }
            DispatchQueue.main.async { self?.onTrigger?() }
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }

    deinit { stop() }
}
