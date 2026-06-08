import AppKit
import SwiftUI

final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

    private init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 1),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "QuickOCR"
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        let hosting = NSHostingView(rootView: PreferencesRootView())
        hosting.translatesAutoresizingMaskIntoConstraints = false
        win.contentView = hosting
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: win.contentView!.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: win.contentView!.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: win.contentView!.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: win.contentView!.bottomAnchor),
        ])
        win.center()
        super.init(window: win)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Root wrapper

private struct PreferencesRootView: View {
    var body: some View {
        PreferencesView()
            .frame(width: 420)
            .fixedSize(horizontal: true, vertical: true)
    }
}

// MARK: - Main view

private struct PreferencesView: View {
    @State private var playSound     = PreferencesManager.shared.playSound
    @State private var launchAtLogin = PreferencesManager.shared.launchAtLogin
    @State private var appeared      = false

    // Shortcut state
    @State private var currentShortcut: ShortcutKey = PreferencesManager.shared.shortcut
    @State private var isRecording    = false
    @State private var heldMods: NSEvent.ModifierFlags = []

    // GitHub hover
    @State private var githubHovered = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            VStack(spacing: 20) {
                generalSection
                shortcutSection
                aboutSection
            }
            .padding(24)
        }
        .background(.background)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { appeared = true }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(hue: 0.60, saturation: 0.70, brightness: 0.95),
                                 Color(hue: 0.72, saturation: 0.60, brightness: 0.80)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 54, height: 54)
                    .shadow(color: Color(hue: 0.65, saturation: 0.5, brightness: 0.6).opacity(0.4),
                            radius: 8, x: 0, y: 4)
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white)
            }
            .scaleEffect(appeared ? 1 : 0.7)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.05), value: appeared)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("QuickOCR")
                        .font(.system(size: 18, weight: .semibold))
                    Text("v1.0")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                Text("Instant text capture from your screen")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .offset(x: appeared ? 0 : -8)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.1), value: appeared)

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 20)
    }

    // MARK: General

    private var generalSection: some View {
        CardSection(label: "General") {
            PrefRow(icon: "speaker.wave.2.fill", color: .orange,
                    title: "Sound Effects",
                    subtitle: "Play a sound when OCR completes",
                    isOn: $playSound)
                .onChange(of: playSound) { v in PreferencesManager.shared.playSound = v }

            RowDivider()

            PrefRow(icon: "arrow.up.right.circle.fill", color: .green,
                    title: "Launch at Login",
                    subtitle: "Start QuickOCR automatically when you log in",
                    isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { v in PreferencesManager.shared.launchAtLogin = v }
        }
        .slideUp(appeared, delay: 0.12)
    }

    // MARK: Shortcut

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Keyboard Shortcut")

            // Card
            VStack(spacing: 0) {
                shortcutRow
                if let warning = currentShortcut.conflictWarning, !isRecording {
                    Divider().padding(.leading, 52).opacity(0.5)
                    conflictBanner(warning)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
            }
            // Pulsing accent border while recording
            .overlay {
                if isRecording { PulsingBorder() }
            }
            // Invisible key-capture overlay while recording
            .overlay {
                if isRecording {
                    ShortcutCaptureView(
                        onCapture: { kc, mods, char in
                            applyShortcut(ShortcutKey(keyCode: kc, modifiers: mods, character: char))
                        },
                        onCancel: {
                            withAnimation(.spring(response: 0.3)) {
                                isRecording = false
                                heldMods = []
                            }
                        },
                        onModsChanged: { mods in
                            withAnimation(.easeOut(duration: 0.08)) { heldMods = mods }
                        }
                    )
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isRecording)
            .animation(.spring(response: 0.35, dampingFraction: 0.8),
                       value: currentShortcut.conflictWarning != nil)

            // Reset button — appears below card when shortcut differs from default
            if !currentShortcut.isDefault {
                HStack {
                    Spacer()
                    Button { withAnimation(.spring(response: 0.35)) { applyShortcut(.default) } } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Reset to Default  ⌘⇧1")
                        }
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity.combined(with: .offset(y: -5)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: currentShortcut.isDefault)
        .slideUp(appeared, delay: 0.20)
    }

    private var shortcutRow: some View {
        HStack(spacing: 10) {
            // Icon — switches to a record dot while recording
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isRecording ? Color.red.opacity(0.15) : Color.accentColor.opacity(0.13))
                    .frame(width: 28, height: 28)
                Image(systemName: isRecording ? "record.circle" : "keyboard")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isRecording ? Color.red : Color.accentColor)
            }
            .animation(.easeOut(duration: 0.2), value: isRecording)

            VStack(alignment: .leading, spacing: 1) {
                Text("Capture Screen Region")
                    .font(.system(size: 13, weight: .medium))
                if isRecording {
                    Text("Press a combo, Esc to cancel")
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.8))
                        .transition(.opacity)
                } else {
                    Text("Click the shortcut badge to change")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isRecording)

            Spacer()

            // Badge area / recording preview
            shortcutBadgeArea
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private var shortcutBadgeArea: some View {
        if isRecording {
            // Live modifier preview while the user is building the combo
            let modParts = modParts(for: heldMods)
            HStack(spacing: 3) {
                if modParts.isEmpty {
                    Text("…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.quaternary)
                        .frame(minWidth: 28)
                } else {
                    ForEach(modParts, id: \.self) { KeyBadge($0).opacity(0.55) }
                    Text("?")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.quaternary)
                }
            }
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        } else {
            // Clickable badge — tap to start recording
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    isRecording = true
                    heldMods = []
                }
            } label: {
                HStack(spacing: 3) {
                    ForEach(currentShortcut.displayComponents, id: \.self) { KeyBadge($0) }
                    Image(systemName: "pencil")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 2)
                }
            }
            .buttonStyle(.plain)
            .help("Click to record a new shortcut")
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }

    private func conflictBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.orange.opacity(0.07))
    }

    private func applyShortcut(_ sc: ShortcutKey) {
        currentShortcut = sc
        isRecording = false
        heldMods = []
        PreferencesManager.shared.shortcut = sc
    }

    private func modParts(for flags: NSEvent.ModifierFlags) -> [String] {
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option)  { parts.append("⌥") }
        if flags.contains(.shift)   { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        return parts
    }

    // MARK: About

    private var aboutSection: some View {
        VStack(spacing: 14) {
            Divider().opacity(0.5)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Made by Vishal")
                        .font(.system(size: 13, weight: .medium))
                    Text("Built with Swift & Vision framework")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                githubButton
            }
        }
        .slideUp(appeared, delay: 0.28)
    }

    private var githubButton: some View {
        Link(destination: URL(string: "https://github.com/VishalT25")!) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                Text("VishalT25")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(githubHovered ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(githubHovered ? Color.accentColor : Color.primary.opacity(0.07))
            )
            .animation(.easeOut(duration: 0.15), value: githubHovered)
        }
        .buttonStyle(.plain)
        .onHover { githubHovered = $0 }
    }
}

// MARK: - Shortcut capture (invisible NSView that grabs key events)

private struct ShortcutCaptureView: NSViewRepresentable {
    var onCapture: (UInt16, NSEvent.ModifierFlags, String) -> Void
    var onCancel: () -> Void
    var onModsChanged: (NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> CaptureNSView { CaptureNSView() }

    func updateNSView(_ nsView: CaptureNSView, context: Context) {
        nsView.onCapture    = onCapture
        nsView.onCancel     = onCancel
        nsView.onModsChanged = onModsChanged
        // Become first responder asynchronously so the view is in the hierarchy
        DispatchQueue.main.async { _ = nsView.window?.makeFirstResponder(nsView) }
    }

    class CaptureNSView: NSView {
        var onCapture:    ((UInt16, NSEvent.ModifierFlags, String) -> Void)?
        var onCancel:     (() -> Void)?
        var onModsChanged: ((NSEvent.ModifierFlags) -> Void)?

        private let relevant: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { onCancel?(); return }  // Escape → cancel
            let mods = event.modifierFlags.intersection(relevant)
            guard !mods.isEmpty else { return }              // bare keys disallowed
            let char = (event.charactersIgnoringModifiers ?? "").uppercased()
            onCapture?(event.keyCode, mods, char.isEmpty ? "?" : char)
        }

        override func flagsChanged(with event: NSEvent) {
            onModsChanged?(event.modifierFlags.intersection(relevant))
        }
    }
}

// MARK: - Pulsing recording border

private struct PulsingBorder: View {
    @State private var on = false

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.accentColor.opacity(on ? 1.0 : 0.25), lineWidth: 2)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

// MARK: - Shared sub-views

private struct CardSection<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(label)
            VStack(spacing: 0) { content() }
                .background(.regularMaterial,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75))
        }
    }
}

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.leading, 4)
    }
}

private struct PrefRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(color).frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isOn)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(hovered ? Color.primary.opacity(0.04) : .clear)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .onHover { hovered = $0 }
        .contentShape(Rectangle())
    }
}

private struct RowDivider: View {
    var body: some View {
        Divider().padding(.leading, 54).opacity(0.6)
    }
}

private struct KeyBadge: View {
    let key: String
    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.12), radius: 0, x: 0, y: 1)
            )
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
    }
}

// MARK: - Animation helper

private extension View {
    func slideUp(_ appeared: Bool, delay: Double) -> some View {
        self
            .offset(y: appeared ? 0 : 12)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(delay), value: appeared)
    }
}
