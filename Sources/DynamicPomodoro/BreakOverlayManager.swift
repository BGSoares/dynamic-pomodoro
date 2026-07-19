import AppKit
import SwiftUI

/// Owns the full-screen break panels — one per connected display.
///
/// Primary panel (the one under the cursor) hosts the SwiftUI timer/controls.
/// Secondary panels are opaque black blockers so the user can't sneak work
/// onto another screen during a break.
@MainActor
final class BreakOverlayManager {
    private var windows: [NSWindow] = []
    private var screenObserver: NSObjectProtocol?
    private let timer: TimerEngine

    init(timer: TimerEngine) {
        self.timer = timer
    }

    func show() {
        buildPanels(alpha: 0)

        NSApp.activate(ignoringOtherApps: true)
        // The 4s fade-in IS the prep — slow enough for the user to finish a thought.
        NSApp.requestUserAttention(.informationalRequest)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 4.0
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            windows.forEach { $0.animator().alphaValue = 1.0 }
        }

        // Displays can come and go mid-break (cable, display sleep, Sidecar).
        // Rebuild the panel set so every connected display stays covered —
        // a screen plugged in mid-break must not become an uncovered workspace.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuildForScreenChange() }
        }
    }

    func hide() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        let current = windows
        guard current.contains(where: { $0.isVisible }) else { return }
        // Clear synchronously so a show() racing with this fade-out
        // doesn't operate on windows we're tearing down.
        windows.removeAll()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 1.5
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            current.forEach { $0.animator().alphaValue = 0 }
        } completionHandler: {
            current.forEach { $0.orderOut(nil) }
        }
    }

    // MARK: - Private

    private func buildPanels(alpha: CGFloat) {
        let primaryScreen = currentScreen()
        windows = NSScreen.screens.map {
            makePanel(for: $0, isPrimary: $0 == primaryScreen)
        }
        for w in windows {
            w.alphaValue = alpha
            w.orderFrontRegardless()
        }
        windows.first { $0.contentViewController != nil }?.makeKeyAndOrderFront(nil)
    }

    /// Swap in a fresh panel set at full opacity — the break is already
    /// underway, so no fade. Old panels are ordered out only after the new
    /// ones are frontmost, leaving no uncovered frame in between.
    private func rebuildForScreenChange() {
        guard !windows.isEmpty else { return }
        let old = windows
        buildPanels(alpha: 1)
        old.forEach { $0.orderOut(nil) }
    }

    /// Anchor to the screen with the cursor — not the key-window screen —
    /// so the timer lands where the user is actually looking.
    private func currentScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func makePanel(for screen: NSScreen, isPrimary: Bool) -> NSPanel {
        let panel = KeyablePanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        if isPrimary {
            let host = NSHostingController(rootView: BreakOverlayView(timer: timer))
            // SwiftUI must never drive the panel's size: on macOS 26,
            // assigning a hosting controller resizes a borderless panel to
            // the view's fitting size, collapsing the full-screen cover to a
            // small floating card. Pin the frame back to the screen.
            host.sizingOptions = []
            panel.contentViewController = host
            panel.setFrame(screen.frame, display: false)
        } else {
            panel.ignoresMouseEvents = true
        }
        // Shielding level sits above native fullscreen apps. `.screenSaver`
        // is too low on modern macOS — apps in their own fullscreen Space
        // punch through it.
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        return panel
    }
}

/// Borderless panels are non-key by default; opt in so SwiftUI gestures and
/// keyboard shortcuts route correctly through the responder chain.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
