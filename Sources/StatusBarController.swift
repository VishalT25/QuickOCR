import AppKit

final class StatusBarController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var captureTask: Task<Void, Never>?

    init() {
        setupButton()
        buildMenu()

        HotkeyManager.shared.onTrigger = { [weak self] in self?.triggerCapture() }
        HotkeyManager.shared.start()

        // Keep the history menu in sync whenever HistoryManager mutates
        HistoryManager.shared.onChanged = { [weak self] in
            DispatchQueue.main.async { self?.refreshHistoryMenu() }
        }
    }

    // MARK: – Button

    private func setupButton() {
        guard let btn = item.button else { return }
        btn.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "QuickOCR")
        btn.image?.isTemplate = true
        btn.toolTip = "QuickOCR"
    }

    // MARK: – Menu

    private func buildMenu() {
        let menu = NSMenu()

        let captureItem = NSMenuItem(title: "Capture", action: #selector(captureAction), keyEquivalent: "")
        captureItem.target = self
        applyCaptureShortcut(to: captureItem)
        menu.addItem(captureItem)

        let historyItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        historyItem.submenu = NSMenu(title: "History")
        menu.addItem(historyItem)

        menu.addItem(.separator())

        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit QuickOCR", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        item.menu = menu
        refreshHistoryMenu()
    }

    // Sets keyEquivalent + mask so AppKit renders the shortcut right-aligned in the native glyph column.
    private func applyCaptureShortcut(to item: NSMenuItem) {
        let sc = PreferencesManager.shared.shortcut
        item.keyEquivalent = sc.character.lowercased()
        item.keyEquivalentModifierMask = sc.modifiers
    }

    func refreshHistoryMenu() {
        guard let menu = item.menu,
              let historyItem = menu.item(withTitle: "History"),
              let sub = historyItem.submenu
        else { return }

        // Keep the capture shortcut in sync with the user's current setting
        if let captureItem = menu.item(withTitle: "Capture") {
            applyCaptureShortcut(to: captureItem)
        }

        sub.removeAllItems()
        let entries = HistoryManager.shared.items

        if entries.isEmpty {
            let empty = NSMenuItem(title: "Nothing yet.", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            sub.addItem(empty)
        } else {
            // Show last 10 in the quick-access submenu
            let recent = Array(entries.prefix(10))
            for (i, entry) in recent.enumerated() {
                var label = entry.text.replacingOccurrences(of: "\n", with: " ")
                if label.count > 40 { label = String(label.prefix(40)) + "…" }
                let mi = NSMenuItem(title: label, action: #selector(copyHistoryEntry(_:)), keyEquivalent: "")
                mi.target = self
                mi.tag = i
                sub.addItem(mi)
            }
        }

        sub.addItem(.separator())

        // "Show All History…" always present (even when empty, so the window is discoverable)
        let showAll = NSMenuItem(title: "Show All History…", action: #selector(openHistory), keyEquivalent: "")
        showAll.target = self
        sub.addItem(showAll)

        if !entries.isEmpty {
            let clear = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
            clear.target = self
            sub.addItem(clear)
        }
    }

    // MARK: – Actions

    @objc private func captureAction() { triggerCapture() }

    @MainActor @objc private func copyHistoryEntry(_ sender: NSMenuItem) {
        let entries = HistoryManager.shared.items
        guard sender.tag < entries.count else { return }
        let text = entries[sender.tag].text
        copyToPasteboard(text)
        let wc = text.split(whereSeparator: \.isWhitespace).count
        ToastController.shared.show(.success(text: text, wordCount: wc), near: item.button)
    }

    @objc private func clearHistory() {
        HistoryManager.shared.clear()
    }

    @objc private func openHistory() {
        HistoryWindowController.shared.show()
    }

    @objc private func openPreferences() {
        PreferencesWindowController.shared.show()
    }

    // MARK: – Capture pipeline

    func triggerCapture() {
        captureTask?.cancel()
        captureTask = Task { await runCapture() }
    }

    @MainActor
    private func runCapture() async {
        let btn = item.button

        try? await Task.sleep(for: .milliseconds(150))

        guard let path = await CaptureManager.shared.captureRegion() else { return }

        ToastController.shared.show(.processing, near: btn)

        do {
            let text = try await CaptureManager.shared.performOCR(at: path)
            try? FileManager.default.removeItem(atPath: path)

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                ToastController.shared.show(.error("No text found."), near: btn)
                return
            }

            copyToPasteboard(trimmed)
            HistoryManager.shared.add(text: trimmed)

            if PreferencesManager.shared.playSound {
                // Bundle.main works inside .app; Bundle.module works during SPM dev
                let url = Bundle.main.url(forResource: "complete", withExtension: "wav")
                       ?? Bundle.module.url(forResource: "complete", withExtension: "wav")
                if let url { NSSound(contentsOf: url, byReference: false)?.play() }
            }

            let wc = trimmed.split(whereSeparator: \.isWhitespace).count
            ToastController.shared.show(.success(text: trimmed, wordCount: wc), near: btn)

        } catch {
            try? FileManager.default.removeItem(atPath: path)
            ToastController.shared.show(.error("OCR failed."), near: btn)
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
