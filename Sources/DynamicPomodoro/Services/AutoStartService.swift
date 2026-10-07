import AppKit
import Combine
import SwiftUI

/// Owns both auto-start countdown triggers end to end, and the machinery
/// they share: the gate decision, the countdown timer, and the floating HUD
/// panel. Renamed from `UnlockAutoStartService` now that a second trigger
/// exists — SPEC_UNLOCK_AUTOSTART.md's unlock trigger stays authoritative
/// for that half; SPEC_LOOP_CONTINUITY.md §2 adds the skip trigger and §6.5
/// the call gate.
@MainActor
final class AutoStartService: ObservableObject {
    @Published private(set) var isCountingDown = false
    /// Live seconds remaining, read by `CountdownHUDView`.
    @Published private(set) var secondsRemaining: Int = 0
    /// Countdown length at the moment it started, for the HUD's ring progress.
    @Published private(set) var totalSeconds: Int = 0

    private let timer: TimerEngine
    private let settings: Settings
    private let log: SessionLogStore
    private let callProbe: () -> Bool
    /// Cancelling either countdown opens the main window
    /// (SPEC_LOOP_CONTINUITY.md §4.2) — injected so this service, like
    /// `TimerEngine`, stays AppKit-free for tests.
    var onCancelPresentsWindow: () -> Void = {}

    private var panel: NSPanel?
    private var countdownTimer: Timer?
    private var deadline: Date?

    init(
        timer: TimerEngine,
        settings: Settings = .shared,
        log: SessionLogStore = .shared,
        callProbe: @escaping () -> Bool = CallDetectionService.isOnCall
    ) {
        self.timer = timer
        self.settings = settings
        self.log = log
        self.callProbe = callProbe
    }

    // MARK: - Trigger handling

    /// Entry point for a real unlock (routed through `ScreenLockMonitor`),
    /// and — unchanged — for the DEBUG "Simulate unlock" menu item, so the
    /// HUD is exercisable without actually locking the machine.
    func handleUnlock(now: Date = Date()) {
        offer(now: now)
    }

    /// Entry point for a completed hold-to-skip (SPEC_LOOP_CONTINUITY.md
    /// §2), fed by the reducer's `.offerAutoStart` effect. The call-cap skip
    /// (an owed break that outlived a 30-minute call) is a different
    /// reducer branch that never emits that effect, so it never reaches
    /// here (§2.2) — only the hold-to-skip path does.
    func offerAfterSkip(now: Date = Date()) {
        offer(now: now)
    }

    /// Shared gate for both triggers. `UnlockGate`'s date-based clauses
    /// are unaffected by principle 7; the call check sits here, beside the
    /// `isCountingDown` guard, because it's a live environment query rather
    /// than a decision about dates (§6.5).
    private func offer(now: Date) {
        guard !isCountingDown else { return }
        // A call suppresses the offer outright: no HUD, no session — a later
        // unlock inside the window still offers once the call ends.
        guard !callProbe() else { return }
        guard UnlockGate.shouldOffer(
            phase: timer.state.phase,
            lastActivityEnd: log.entries.last?.endedAt,
            now: now,
            windowMinutes: settings.autoStartWindowMinutes
        ) else { return }
        startCountdown(now: now)
    }

    /// A lock while the countdown is up means the user saw the HUD, locked
    /// again, and left — dismiss quietly; the next unlock offers again. This
    /// also rules out the worst outcome: a session auto-starting into a
    /// locked, empty room.
    func handleLock() {
        cancelCountdown(byUser: false)
    }

    // MARK: - Countdown

    private func startCountdown(now: Date) {
        totalSeconds = settings.autoStartCountdownSeconds
        secondsRemaining = totalSeconds
        deadline = now.addingTimeInterval(TimeInterval(totalSeconds))
        isCountingDown = true
        showPanel()

        countdownTimer?.invalidate()
        // `.common` mode so the countdown keeps advancing during modal
        // event-tracking loops, matching `TimerEngine.startTicker()`.
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        countdownTimer = t
    }

    private func tick() {
        guard let deadline else { return }
        let now = Date()
        secondsRemaining = max(0, Int(ceil(deadline.timeIntervalSince(now))))
        guard secondsRemaining == 0 else { return }

        guard UnlockGate.shouldStillFire(deadline: deadline, now: now) else {
            // Overslept the deadline (sleep, stalled run loop) — nobody was
            // there to see it end; don't fabricate a start on their behalf.
            cancelCountdown(byUser: false)
            return
        }

        countdownTimer?.invalidate()
        countdownTimer = nil
        self.deadline = nil
        isCountingDown = false
        hidePanel()
        // Same call the Idle screen button and "Start focus" menu item make —
        // the trigger differs, nothing downstream does.
        timer.startFocus(now: now)
    }

    /// Cancel the active countdown. `byUser: true` (a click on the card, Esc,
    /// the status-item click) opens the main window (§4.2) — the cancel is
    /// proof someone is there; `byUser: false` (locked again, deadline
    /// overshoot) opens nothing, because nobody asked for a window.
    func cancelCountdown(byUser: Bool) {
        guard isCountingDown else { return }
        countdownTimer?.invalidate()
        countdownTimer = nil
        deadline = nil
        isCountingDown = false
        hidePanel()
        if byUser { onCancelPresentsWindow() }
    }

    // MARK: - Panel

    private func showPanel() {
        let panel = makePanel()
        self.panel = panel
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func hidePanel() {
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = CountdownPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.onCancel = { [weak self] in self?.cancelCountdown(byUser: true) }
        // `.nonactivatingPanel` + never calling NSApp.activate: the HUD can
        // become key (so Esc reaches it) without stealing foreground from
        // whatever app the user is actually looking at.
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        // No implicit panel animations (macOS 26 can wedge a borderless
        // panel at its initial state) — our own alpha fade is the only one.
        panel.animationBehavior = .none

        // Size the panel to the card; the panel is exactly as big as what it shows.
        let host = FirstClickHostingView(rootView: CountdownHUDView(service: self))
        panel.setContentSize(host.fittingSize)
        panel.contentView = host

        if let screen = currentScreen() {
            let size = panel.frame.size
            let visible = screen.visibleFrame
            let origin = NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.maxY - size.height - visible.height * 0.12
            )
            panel.setFrameOrigin(origin)
        }
        return panel
    }

    /// Anchor to the screen with the cursor, mirroring
    /// `BreakOverlayManager.currentScreen()` — the countdown should land
    /// where the user is actually looking, not on the key-window's screen.
    private func currentScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}

/// The card is clicked to cancel, usually while the panel isn't key (the
/// user unlocked into another app, or clicked one). Without first-mouse
/// acceptance that click would only make the panel key and the card would
/// seem dead; with it, the first click is the cancel.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Borderless, non-activating panel that still becomes key so Esc reaches it
/// through the normal responder chain — deliberately not a global event
/// monitor, which would require Input Monitoring permission.
private final class CountdownPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
