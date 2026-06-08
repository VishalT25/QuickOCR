import AppKit
import Foundation
import ServiceManagement

// MARK: - Shortcut model

struct ShortcutKey: Equatable {
    let keyCode:   UInt16
    let modifiers: NSEvent.ModifierFlags   // only .command / .shift / .option / .control
    let character: String                  // upper-cased display character captured at record time

    static let `default` = ShortcutKey(keyCode: 18, modifiers: [.command, .shift], character: "1")

    var isDefault: Bool { self == .default }

    // Ordered display symbols, standard macOS modifier order
    var displayComponents: [String] {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option)  { parts.append("⌥") }
        if modifiers.contains(.shift)   { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(displayKey)
        return parts
    }

    // Readable key name (handles special keys by code)
    var displayKey: String {
        switch keyCode {
        case 36: return "↩";  case 48: return "⇥";   case 49: return "Space"
        case 51: return "⌫";  case 53: return "⎋"
        case 122: return "F1"; case 120: return "F2"; case 99:  return "F3"
        case 118: return "F4"; case 96:  return "F5"; case 97:  return "F6"
        case 98:  return "F7"; case 100: return "F8"; case 101: return "F9"
        case 109: return "F10";case 103: return "F11";case 111: return "F12"
        default: return character.isEmpty ? "?" : character.uppercased()
        }
    }

    // Returns a human-readable warning if this combo is likely to conflict
    var conflictWarning: String? {
        if modifiers.isEmpty {
            return "Without a modifier key this will interfere with normal typing."
        }
        if modifiers == .shift {
            return "Shift-only shortcuts conflict with uppercase text input."
        }
        let known: [(UInt16, NSEvent.ModifierFlags, String)] = [
            (49, [.command],         "Spotlight Search (⌘Space)"),
            (48, [.command],         "App Switcher (⌘Tab)"),
            (20, [.command, .shift], "Screenshot — 3 (⌘⇧3)"),
            (21, [.command, .shift], "Screenshot — 4 (⌘⇧4)"),
            (23, [.command, .shift], "Screenshot — 5 (⌘⇧5)"),
            (49, [.control],         "Input Source Switch"),
        ]
        for (kc, mods, name) in known where kc == keyCode && mods == modifiers {
            return "Likely conflicts with \(name)."
        }
        return nil
    }
}

// MARK: - Preferences store

final class PreferencesManager {
    static let shared = PreferencesManager()
    private let defaults = UserDefaults.standard
    private init() {}

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: "hasCompletedOnboarding") }
        set { defaults.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    var playSound: Bool {
        get { defaults.object(forKey: "playSound") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "playSound") }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: "launchAtLogin") }
        set {
            defaults.set(newValue, forKey: "launchAtLogin")
            setLoginItem(enabled: newValue)
        }
    }

    var shortcut: ShortcutKey {
        get {
            guard defaults.object(forKey: "shortcutKeyCode") != nil else { return .default }
            let keyCode = UInt16(clamping: max(0, defaults.integer(forKey: "shortcutKeyCode")))
            let mods    = NSEvent.ModifierFlags(rawValue: UInt(max(0, defaults.integer(forKey: "shortcutModifiers"))))
            let char    = defaults.string(forKey: "shortcutCharacter") ?? "1"
            return ShortcutKey(keyCode: keyCode, modifiers: mods, character: char)
        }
        set {
            defaults.set(Int(newValue.keyCode),              forKey: "shortcutKeyCode")
            defaults.set(Int(newValue.modifiers.rawValue),   forKey: "shortcutModifiers")
            defaults.set(newValue.character,                 forKey: "shortcutCharacter")
        }
    }

    private func setLoginItem(enabled: Bool) {
        if #available(macOS 13, *) {
            do {
                if enabled { try SMAppService.mainApp.register() }
                else        { try SMAppService.mainApp.unregister() }
            } catch {}
        }
    }
}
