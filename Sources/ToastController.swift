import AppKit
import SwiftUI

@MainActor
final class ToastController {
    static let shared = ToastController()

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ state: ToastState, near button: NSStatusBarButton?) {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.close()
        panel = nil

        // ── 1. Resolve the button's screen position ────────────────────────────
        // win.frame is always in global screen coordinates (AppKit guarantee).
        // btn.frame.midX is the button's centre X within the window's content area.
        // Because the status-bar window's content view fills the window exactly,
        // win.frame.minX + btn.frame.midX gives the button's true screen X without
        // any coordinate-conversion chain (which breaks on external displays due to
        // differing backing scale factors and window types).
        var buttonMidX:   CGFloat   = 0
        var buttonMinY:   CGFloat   = 0
        var targetScreen: NSScreen? = NSScreen.main

        if let btn = button, let win = btn.window {
            let winFrame = win.frame
            buttonMidX   = winFrame.minX + btn.frame.midX
            buttonMinY   = winFrame.minY
            // Use the window frame (not the converted button rect) to find the screen —
            // it spans the full width of whatever display the menu bar is on.
            targetScreen = NSScreen.screens.first(where: { $0.frame.intersects(winFrame) })
                           ?? NSScreen.main
        }

        // ── 2. Panel X: center on button, clamp to screen edges ────────────────
        let toastWidth: CGFloat = 300
        var panelX = buttonMidX - toastWidth / 2
        if let sv = targetScreen?.visibleFrame {
            panelX = max(sv.minX + 8, min(panelX, sv.maxX - toastWidth - 8))
        }

        // ── 3. tipX: button midpoint relative to panel's left edge ─────────────
        let tipX = buttonMidX - panelX

        // ── 4. Build SwiftUI content and measure natural height ─────────────────
        let hosting = NSHostingView(rootView: ToastView(state: state, tipX: tipX))
        hosting.frame = NSRect(x: 0, y: 0, width: toastWidth, height: 2000)
        let fittedHeight = max(hosting.fittingSize.height, 64)
        let size = NSSize(width: toastWidth, height: fittedHeight)
        hosting.frame = NSRect(origin: .zero, size: size)

        // ── 5. Create NSPanel ───────────────────────────────────────────────────
        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        p.contentView       = hosting
        p.backgroundColor   = .clear
        p.isOpaque          = false
        p.hasShadow         = false   // shadow is rendered inside SwiftUI
        p.isFloatingPanel   = true
        p.level             = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        // ── 6. Position: further below the menu bar button ─────────────────────
        let panelY = buttonMinY - size.height - 16
        p.setFrameOrigin(NSPoint(x: panelX, y: panelY))

        // Slide-in: start 8 pt higher (closer to menu bar), fade in
        let dest = p.frame.origin
        p.setFrameOrigin(NSPoint(x: dest.x, y: dest.y + 8))
        p.alphaValue = 0
        p.orderFront(nil)
        panel = p

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration       = 0.22
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0.1, 1)
            p.animator().alphaValue = 1
            p.animator().setFrameOrigin(dest)
        }

        // ── 7. Auto-dismiss ────────────────────────────────────────────────────
        let duration: Double? = switch state {
            case .processing: nil
            case .success:    4.0
            case .error:      3.0
        }

        if let duration {
            dismissTask = Task {
                try? await Task.sleep(for: .seconds(duration))
                guard !Task.isCancelled else { return }
                dismiss()
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        guard let p = panel else { return }
        panel = nil

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration       = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().alphaValue = 0
        }, completionHandler: { p.close() })
    }
}
