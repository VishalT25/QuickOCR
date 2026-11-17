import AppKit
import Carbon.HIToolbox

/// Registers the capture shortcut as a system hotkey (Carbon RegisterEventHotKey).
/// Unlike an NSEvent global monitor, this needs no Accessibility / Input Monitoring
/// permission, so it keeps working after macOS updates reset privacy grants.
final class HotkeyManager {
    static let shared = HotkeyManager()

    var onTrigger: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {}

    func start() {
        installHandlerIfNeeded()
        register()
    }

    /// Re-registers using the current shortcut from preferences.
    func reload() {
        unregister()
        register()
    }

    func stop() {
        unregister()
        if let h = handlerRef { RemoveEventHandler(h) }
        handlerRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { mgr.onTrigger?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    private func register() {
        let sc = PreferencesManager.shared.shortcut
        var mods: UInt32 = 0
        if sc.modifiers.contains(.command) { mods |= UInt32(cmdKey) }
        if sc.modifiers.contains(.shift)   { mods |= UInt32(shiftKey) }
        if sc.modifiers.contains(.option)  { mods |= UInt32(optionKey) }
        if sc.modifiers.contains(.control) { mods |= UInt32(controlKey) }

        let id = EventHotKeyID(signature: OSType(0x514F4352), id: 1) // 'QOCR'
        let status = RegisterEventHotKey(UInt32(sc.keyCode), mods, id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            NSLog("QuickOCR: RegisterEventHotKey failed (\(status)) — shortcut may be in use by another app")
        }
    }

    private func unregister() {
        if let r = hotKeyRef { UnregisterEventHotKey(r) }
        hotKeyRef = nil
    }

    deinit { stop() }
}
