import AppKit
import SwiftUI
import CoreGraphics

// MARK: – Steps

private enum OnboardStep: Int, CaseIterable {
    case welcome, accessibility, screenRecording, shortcut, tryItOut, done
}

// MARK: – Window Controller

final class OnboardingWindowController: NSObject {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?
    private override init() {}

    func showIfNeeded() {
        guard !PreferencesManager.shared.hasCompletedOnboarding else { return }
        show()
    }

    private func show() {
        if window == nil { makeWindow() }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func finish() {
        PreferencesManager.shared.hasCompletedOnboarding = true
        window?.close()
        window = nil
    }

    private func makeWindow() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 500),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.contentView = NSHostingView(rootView: OnboardFlow(onFinish: { [weak self] in
            self?.finish()
        }))
        window = w
    }
}

// MARK: – Root flow

private struct OnboardFlow: View {
    let onFinish: () -> Void
    @State private var step = OnboardStep.welcome
    @State private var goingForward = true

    var body: some View {
        ZStack {
            stepView
                .id(step.rawValue)
                .transition(slideTransition)
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.88), value: step.rawValue)
        .frame(width: 520, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var slideTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
            removal:   .move(edge: goingForward ? .leading  : .trailing).combined(with: .opacity)
        )
    }

    @ViewBuilder private var stepView: some View {
        switch step {
        case .welcome:        WelcomeStep(onNext: next)
        case .accessibility:  AccessStep(onNext: next, onBack: back)
        case .screenRecording: ScreenStep(onNext: next, onBack: back)
        case .shortcut:       ShortcutStep(onNext: next, onBack: back)
        case .tryItOut:       TryStep(onNext: next, onBack: back)
        case .done:           DoneStep(onFinish: onFinish)
        }
    }

    private func next() {
        goingForward = true
        if let n = OnboardStep(rawValue: step.rawValue + 1) { step = n }
    }
    private func back() {
        goingForward = false
        if let p = OnboardStep(rawValue: step.rawValue - 1) { step = p }
    }
}

// MARK: – Shared components

private struct ProgressDots: View {
    let current: Int   // 0-based within the 4 middle steps
    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<4) { i in
                Capsule()
                    .fill(i == current ? Color.accentColor : Color.secondary.opacity(0.22))
                    .frame(width: i == current ? 22 : 7, height: 7)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: current)
            }
        }
    }
}

private struct PermPill: View {
    let granted: Bool
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
            Text(granted ? "Granted" : "Not Granted")
                .fontWeight(.medium)
        }
        .font(.system(size: 13))
        .foregroundStyle(granted ? .green : .orange)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background((granted ? Color.green : Color.orange).opacity(0.12), in: Capsule())
        .animation(.spring(response: 0.3), value: granted)
    }
}

// Shared nav bar used by all middle steps
private struct StepNav: View {
    let onBack: () -> Void
    let primaryLabel: String
    let primaryEnabled: Bool
    let onPrimary: () -> Void

    var body: some View {
        HStack {
            Button("← Back", action: onBack)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
            Spacer()
            if primaryEnabled {
                Button(primaryLabel, action: onPrimary).buttonStyle(.borderedProminent)
            } else {
                Button(primaryLabel, action: onPrimary).buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 28)
    }
}

// MARK: – Welcome

private struct WelcomeStep: View {
    let onNext: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Group {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 90, height: 90)
                } else {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .scaleEffect(appeared ? 1 : 0.45)
            .opacity(appeared ? 1 : 0)

            Text("Welcome to QuickOCR")
                .font(.system(size: 26, weight: .bold))
                .padding(.top, 22)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)

            Text("Capture text from anywhere on your screen\nin seconds — all on device, totally private.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 64)
                .padding(.top, 10)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)

            Spacer()

            Button(action: onNext) {
                Text("Get Started")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 170, height: 38)
            }
            .buttonStyle(.borderedProminent)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)

            Spacer().frame(height: 40)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.18)) {
                appeared = true
            }
        }
    }
}

// MARK: – Accessibility

private struct AccessStep: View {
    let onNext: () -> Void
    let onBack: () -> Void
    @State private var granted = AXIsProcessTrusted()
    private let timer = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()

    var body: some View {
        PermLayout(
            dotIndex: 0,
            icon: "accessibility",
            iconColor: .blue,
            title: "Accessibility Access",
            subtitle: "QuickOCR needs Accessibility permission to detect your global shortcut from any app, even when QuickOCR isn't focused.",
            granted: granted,
            settingsURLString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            onNext: onNext,
            onBack: onBack
        )
        .onReceive(timer) { _ in granted = AXIsProcessTrusted() }
    }
}

// MARK: – Screen Recording

private struct ScreenStep: View {
    let onNext: () -> Void
    let onBack: () -> Void
    @State private var granted = CGPreflightScreenCaptureAccess()
    private let timer = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()

    var body: some View {
        PermLayout(
            dotIndex: 1,
            icon: "camera.fill",
            iconColor: .purple,
            title: "Screen Recording",
            subtitle: "QuickOCR captures only the region you drag. Screenshots are deleted immediately after text is extracted. Nothing leaves your Mac.",
            granted: granted,
            settingsURLString: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            onNext: onNext,
            onBack: onBack
        )
        .onReceive(timer) { _ in granted = CGPreflightScreenCaptureAccess() }
    }
}

private struct PermLayout: View {
    let dotIndex: Int
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let granted: Bool
    let settingsURLString: String
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ProgressDots(current: dotIndex).padding(.top, 32)

            Image(systemName: icon)
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(iconColor)
                .padding(.top, 28)

            Text(title)
                .font(.system(size: 22, weight: .bold))
                .padding(.top, 16)

            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 52)
                .padding(.top, 8)

            VStack(spacing: 10) {
                PermPill(granted: granted)

                if !granted {
                    Button("Open System Settings") {
                        if let url = URL(string: settingsURLString) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 13))
                }
            }
            .frame(height: 78)
            .padding(.top, 12)

            Spacer()

            StepNav(
                onBack: onBack,
                primaryLabel: granted ? "Continue →" : "Skip for Now →",
                primaryEnabled: granted,
                onPrimary: onNext
            )
        }
    }
}

// MARK: – Shortcut

private struct ShortcutStep: View {
    let onNext: () -> Void
    let onBack: () -> Void

    private let sc = PreferencesManager.shared.shortcut
    @State private var visible: [Bool]

    init(onNext: @escaping () -> Void, onBack: @escaping () -> Void) {
        self.onNext = onNext
        self.onBack = onBack
        let count = PreferencesManager.shared.shortcut.displayComponents.count
        _visible = State(initialValue: Array(repeating: false, count: count))
    }

    var body: some View {
        VStack(spacing: 0) {
            ProgressDots(current: 2).padding(.top, 32)

            Image(systemName: "keyboard")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 28)

            Text("Your Capture Shortcut")
                .font(.system(size: 22, weight: .bold))
                .padding(.top, 16)

            Text("Press this from any app to start capturing text.\nYou can change it later in Preferences.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 52)
                .padding(.top, 8)

            HStack(spacing: 10) {
                ForEach(Array(sc.displayComponents.enumerated()), id: \.offset) { i, part in
                    Text(part)
                        .font(.system(size: 26, weight: .semibold, design: .monospaced))
                        .frame(width: 58, height: 58)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                        .scaleEffect(visible.indices.contains(i) && visible[i] ? 1 : 0.25)
                        .opacity(visible.indices.contains(i) && visible[i] ? 1 : 0)
                }
            }
            .padding(.top, 30)

            Spacer()

            StepNav(
                onBack: onBack,
                primaryLabel: "Got It →",
                primaryEnabled: true,
                onPrimary: onNext
            )
        }
        .onAppear {
            let comps = sc.displayComponents
            for i in 0..<comps.count {
                withAnimation(
                    .spring(response: 0.38, dampingFraction: 0.58)
                    .delay(0.2 + Double(i) * 0.13)
                ) {
                    if i < visible.count { visible[i] = true }
                }
            }
        }
    }
}

// MARK: – Try It Out

private struct TryStep: View {
    let onNext: () -> Void
    let onBack: () -> Void

    @ObservedObject private var history = HistoryManager.shared
    @State private var initialCount = -1
    @State private var captured = false
    @State private var pulse = false

    private let sc = PreferencesManager.shared.shortcut
    private let demoLines = [
        "Meeting at 3pm in Room 4B",
        "Call John: +1 555 867-5309",
        "Website: apple.com/swift",
    ]

    var body: some View {
        VStack(spacing: 0) {
            ProgressDots(current: 3).padding(.top, 32)

            Image(systemName: captured ? "checkmark.circle.fill" : "cursorarrow.rays")
                .font(.system(size: 52))
                .foregroundStyle(captured ? Color.green : Color.accentColor)
                .padding(.top, 28)
                .animation(.spring(response: 0.4, dampingFraction: 0.65), value: captured)

            Text(captured ? "Captured!" : "Try It Out")
                .font(.system(size: 22, weight: .bold))
                .padding(.top, 16)
                .animation(.spring(), value: captured)

            if captured {
                Text("Text is now in your clipboard. That's all there is to it!")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 52)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            } else {
                VStack(spacing: 3) {
                    HStack(spacing: 5) {
                        ForEach(sc.displayComponents, id: \.self) { c in
                            Text(c)
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.2)))
                        }
                    }
                    Text("then drag a rectangle over the text below")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .offset(y: 6)))
            }

            if !captured {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(demoLines, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 15, design: .monospaced))
                            .foregroundStyle(.primary.opacity(0.85))
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            pulse ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.18),
                            lineWidth: pulse ? 1.8 : 1
                        )
                )
                .scaleEffect(pulse ? 1.012 : 1.0)
                .padding(.horizontal, 36)
                .padding(.top, 18)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)
                .transition(.opacity)
            }

            Spacer()

            HStack {
                Button("← Back", action: onBack)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                Spacer()
                if !captured {
                    Button("Skip") { onNext() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 13))
                        .padding(.trailing, 14)
                }
                if captured {
                    Button("Continue →", action: onNext).buttonStyle(.borderedProminent)
                } else {
                    Button("Skip →", action: onNext).buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 28)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: captured)
        .onAppear {
            initialCount = history.items.count
            pulse = true
        }
        .onChange(of: history.items.count) { newCount in
            if initialCount >= 0, newCount > initialCount, !captured {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    captured = true
                }
            }
        }
    }
}

// MARK: – Done

private struct DoneStep: View {
    let onFinish: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.14))
                    .frame(width: 108, height: 108)
                Image(systemName: "checkmark")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(.green)
            }
            .scaleEffect(appeared ? 1 : 0.3)
            .opacity(appeared ? 1 : 0)
            .rotationEffect(appeared ? .zero : .degrees(-20))

            Text("You're all set!")
                .font(.system(size: 26, weight: .bold))
                .padding(.top, 22)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)

            Text("QuickOCR lives in your menu bar.\nPress your shortcut any time to start capturing.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 60)
                .padding(.top, 10)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)

            Spacer()

            Button(action: onFinish) {
                Text("Start Using QuickOCR")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 210, height: 38)
            }
            .buttonStyle(.borderedProminent)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)

            Spacer().frame(height: 40)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.62).delay(0.1)) {
                appeared = true
            }
        }
    }
}
