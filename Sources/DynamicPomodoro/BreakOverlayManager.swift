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
    private let timer: TimerEngine

    init(timer: TimerEngine) {
        self.timer = timer
    }

    func show() {
        let primaryScreen = currentScreen()
        windows = NSScreen.screens.map {
            makePanel(for: $0, isPrimary: $0 == primaryScreen)
        }

        NSApp.activate(ignoringOtherApps: true)
        for w in windows {
            w.alphaValue = 0
            w.orderFrontRegardless()
        }
        windows.first { $0.contentViewController != nil }?.makeKeyAndOrderFront(nil)

        // The 4s fade-in IS the prep — slow enough for the user to finish a thought.
        NSApp.requestUserAttention(.informationalRequest)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 4.0
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            windows.forEach { $0.animator().alphaValue = 1.0 }
        }
    }

    func hide() {
        let current = windows
        guard current.contains(where: { $0.isVisible }) else { return }
        // Clear synchronously so a screen-change racing with this fade-out
        // doesn't rebuild on top of windows we're tearing down.
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

    /// Anchor to the screen with the cursor — not the key-window screen —
    /// so the timer lands where the user is actually looking.
    private func currentScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        if let s = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return s
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func makePanel(for screen: NSScreen, isPrimary: Bool) -> NSPanel {
        let panel = KeyablePanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        if isPrimary {
            panel.contentViewController = NSHostingController(rootView: BreakOverlayView(timer: timer))
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
