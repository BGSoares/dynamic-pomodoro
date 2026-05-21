import AppKit
import Combine
import Sparkle
import SwiftUI

// Entry point. Uses AppKit directly (rather than SwiftUI's @main App + MenuBarExtra)
// so this builds as a plain SPM executable — no Xcode project or app bundle required.
// Trade-off: we wire menu bar + windows by hand, but gain `swift run` portability.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings.shared
    private let timer = TimerEngine()
    private let notifications = NotificationService.shared
    private let updater = UpdaterService.shared

    private var statusItem: NSStatusItem!
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var breakOverlayWindows: [NSWindow] = []
    private var primaryBreakWindow: NSWindow?
    private let breakPresentation = BreakOverlayPresentation()
    private var breakWindowDelegates: [BreakWindowDelegate] = []
    private var breakOverlayWatchdog: Timer?
    private var phaseCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupMainMenu()
        notifications.requestAuthorizationIfNeeded()
        setupStatusItem()

        openMainWindow()

        // Drive title refresh once per second — cheap, and independent of the
        // engine's internal ticker. Scheduled in `.common` modes so it keeps
        // firing during event tracking (e.g. while the user holds the skip
        // button).
        let titleTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateStatusItemTitle() }
        }
        RunLoop.main.add(titleTimer, forMode: .common)

        // Show/hide the full-screen break overlay in response to phase changes.
        phaseCancellable = timer.$state
            .map(\.phase)
            .removeDuplicates(by: { $0.tag == $1.tag })
            .sink { [weak self] newPhase in
                Task { @MainActor in self?.handlePhaseChange(newPhase) }
            }

        // If displays change mid-break, rebuild the overlay panels against the
        // new screen set — otherwise stale frames make SwiftUI hit-testing
        // drift off the visible content (clicks on the buttons "do nothing").
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleScreenParametersChanged() }
        }
    }

    // MARK: - Break overlay

    private func handlePhaseChange(_ phase: PomodoroState.Phase) {
        switch phase {
        case .breakRunning:
            showBreakOverlay()
        case .idle, .focus:
            hideBreakOverlay()
        }
    }

    /// The break interrupts whatever the user is doing right now, so anchor the
    /// overlay to the screen with the cursor — not whichever screen happens to
    /// hold the key window (which is what `NSScreen.main` returns).
    private func currentBreakScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        if let s = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return s
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    /// Build one window per connected display and slide each into its own
    /// native fullscreen Space. The primary window hosts the SwiftUI timer/UI;
    /// the rest paint the same dark backdrop so secondary screens look like
    /// the same break, not a separate event.
    ///
    /// Because each window owns its fullscreen Space, the overlay covers
    /// other apps' fullscreen content too — `.canJoinAllSpaces` /
    /// `.fullScreenAuxiliary` only work *within an app's own* fullscreen
    /// Space, so they couldn't reach a code editor in fullscreen on the same
    /// display. Toggling fullscreen on our own window sidesteps that
    /// entirely.
    ///
    /// `presentation.contentOpacity` stays at 0 until each window finishes
    /// its Space transition, so the swoosh slides in a flat dark panel — the
    /// user perceives "the screen dimming", not "a window arriving" — and
    /// only then does the timer fade up.
    /// Primary is picked by cursor location so the timer lands on the screen
    /// the user is actually looking at — `NSScreen.main` returns the screen
    /// with the key window, often a different display.
    private func showBreakOverlay() {
        let primaryScreen = currentBreakScreen()
        breakPresentation.contentOpacity = 0

        // Order screens so primary (where the cursor is) goes first. Coverage
        // lands on the user's active display before the rest follow, which
        // matters because the swoosh on primary is the one they actually see.
        var orderedScreens = NSScreen.screens
        if let primary = primaryScreen,
           let idx = orderedScreens.firstIndex(of: primary) {
            orderedScreens.remove(at: idx)
            orderedScreens.insert(primary, at: 0)
        }

        // Per-window delegate so we can chain the entry sequence and so the
        // watchdog can detect lost fullscreen state per window.
        breakOverlayWindows = []
        breakWindowDelegates = []
        primaryBreakWindow = nil
        for screen in orderedScreens {
            let isPrimary = screen == primaryScreen
            let delegate = BreakWindowDelegate()
            let window = makeBreakWindow(for: screen, isPrimary: isPrimary, delegate: delegate)
            breakOverlayWindows.append(window)
            breakWindowDelegates.append(delegate)
            if isPrimary { primaryBreakWindow = window }
        }

        // Toggling all windows fullscreen in the same runloop tick produces
        // races on extended displays — macOS handles each per-display Space
        // transition fine in isolation but routes simultaneous requests to
        // the wrong display, leaving secondary screens as bare desktop. Enter
        // one window at a time, driven by each delegate's
        // `windowDidEnterFullScreen` callback.
        //
        // No `NSApp.activate` before this loop: activating from a background
        // app would Space-switch the user out of any other-app fullscreen
        // Space into our desktop Space, then `toggleFullScreen` would
        // Space-switch again — two swooshes back-to-back. Going straight to
        // `toggleFullScreen` makes macOS animate from the user's current
        // Space into our new fullscreen Space in a single transition.
        enterFullScreenInSequence(at: 0)
    }

    private func enterFullScreenInSequence(at index: Int) {
        guard index < breakOverlayWindows.count else {
            // All displays now own their break Space.
            fadeBreakContentIn()
            startBreakOverlayWatchdog()
            return
        }
        let window = breakOverlayWindows[index]
        let delegate = breakWindowDelegates[index]
        delegate.onNextEnterFullScreen = { [weak self] in
            self?.enterFullScreenInSequence(at: index + 1)
        }
        window.orderFrontRegardless()
        window.toggleFullScreen(nil)

        // Safety net: if `windowDidEnterFullScreen` never fires (some macOS
        // multi-display edge cases swallow it), force-advance after 3 s. The
        // delegate is one-shot, so if it already fired this branch sees
        // `onNextEnterFullScreen == nil` and bails.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self, weak delegate] in
            guard delegate?.onNextEnterFullScreen != nil else { return }
            delegate?.onNextEnterFullScreen = nil
            self?.enterFullScreenInSequence(at: index + 1)
        }
    }

    private func fadeBreakContentIn() {
        // Now that we own the visible Space, take focus so the skip button
        // and any future keyboard handling route to us.
        NSApp.activate(ignoringOtherApps: true)
        primaryBreakWindow?.makeKey()
        NSApp.requestUserAttention(.informationalRequest)
        withAnimation(.easeInOut(duration: 4.0)) {
            breakPresentation.contentOpacity = 1
        }
    }

    /// Heartbeat that re-asserts the front-most fullscreen state of every
    /// break window. Defensive against three failure modes that have shown
    /// up in similar overlay apps (e.g. wnr's recurring `setKiosk` re-call):
    ///   1. User presses ⌃⌘F or uses Mission Control to escape fullscreen
    ///   2. Another app's focus management pulls a window above ours
    ///   3. macOS demotes a fullscreen window during an unrelated display
    ///      reconfiguration
    /// We only re-toggle when the window is clearly NOT in fullscreen —
    /// toggling during the system's own transition produces undefined
    /// behavior, and the watchdog starts only after every window has
    /// finished entering, so the steady-state path is a cheap no-op.
    private func startBreakOverlayWatchdog() {
        breakOverlayWatchdog?.invalidate()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.assertBreakOverlayActive() }
        }
        RunLoop.main.add(timer, forMode: .common)
        breakOverlayWatchdog = timer
    }

    private func stopBreakOverlayWatchdog() {
        breakOverlayWatchdog?.invalidate()
        breakOverlayWatchdog = nil
    }

    private func assertBreakOverlayActive() {
        for window in breakOverlayWindows {
            // `orderFrontRegardless` on a window already in its own
            // fullscreen Space demotes it out of fullscreen, which the next
            // tick then re-enters — producing a ~2 s swoosh-in / swoosh-out
            // cycle for the whole break. Only re-front when we're actually
            // recovering a demoted window; inside our own Space there's no
            // other-app window to be pulled above us.
            if !window.styleMask.contains(.fullScreen) {
                window.orderFrontRegardless()
                window.toggleFullScreen(nil)
            }
        }
    }

    private func makeBreakWindow(for screen: NSScreen,
                                 isPrimary: Bool,
                                 delegate: BreakWindowDelegate) -> NSWindow {
        // `.titled` + `.fullSizeContentView` is the minimum styleMask that
        // supports `toggleFullScreen`. We then hide the titlebar visually so
        // the result looks identical to a borderless window. Borderless
        // windows don't get the fullscreen affordance, which is why the old
        // panel-based approach couldn't take this path.
        let window = BreakWindow(
            contentRect: screen.frame,
            styleMask: [.titled, .fullSizeContentView, .resizable, .closable],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        if isPrimary {
            window.contentViewController = NSHostingController(
                rootView: BreakOverlayView(timer: timer, presentation: breakPresentation)
            )
            window.ignoresMouseEvents = false
        } else {
            window.contentViewController = NSHostingController(rootView: BreakBackgroundView())
            window.ignoresMouseEvents = true
        }
        // Every window gets a delegate now: primaries need it for content-
        // fade-in chaining, secondaries need it so the entry sequence can
        // wait for each display's Space transition before moving on.
        window.delegate = delegate
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .forEach { window.standardWindowButton($0)?.isHidden = true }
        window.isMovable = false
        // Owning the fullscreen Space is the whole point — primary, not
        // auxiliary, so macOS gives us a dedicated Space we slide into.
        window.collectionBehavior = [.fullScreenPrimary, .stationary]
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        return window
    }

    private func hideBreakOverlay() {
        let windows = breakOverlayWindows
        let delegates = breakWindowDelegates
        guard !windows.isEmpty, let primary = primaryBreakWindow else { return }
        stopBreakOverlayWatchdog()
        // Clear synchronously so a screen-change racing with this teardown
        // doesn't see a stale array and rebuild on top of windows we're
        // tearing down. The closures below own local snapshots.
        breakOverlayWindows.removeAll()
        primaryBreakWindow = nil
        breakWindowDelegates.removeAll()

        let secondaries = windows.filter { $0 !== primary }
        let primaryDelegate = primary.delegate as? BreakWindowDelegate

        // 1) Fade the content (timer/text) out while still fullscreen — the
        //    dark backdrop stays put so the screen visibly "stays dimmed".
        withAnimation(.easeInOut(duration: 1.5)) {
            breakPresentation.contentOpacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // 2) Close secondary windows directly. Their fullscreen Spaces
            //    collapse silently because we never let an exit-fullscreen
            //    animation start — and that's what avoids the black
            //    `screen.frame`-sized rectangle that flashed on those
            //    displays before. The user is looking at the primary screen
            //    during a break, so the absence of a swoosh on secondaries
            //    isn't noticeable.
            for window in secondaries {
                window.orderOut(nil)
                window.contentViewController = nil
            }

            // 3) Swoosh the primary out and `orderOut` precisely on the
            //    delegate's exit callback — no hardcoded settle-time, no
            //    risk of seeing the titled window briefly painted at full
            //    `screen.frame` size on the desktop after the animation
            //    finishes. `delegates` is captured to anchor `primaryDelegate`
            //    across the async boundary; the ivar was cleared above.
            primaryDelegate?.onNextExitFullScreen = { [weak primary] in
                primary?.orderOut(nil)
                primary?.contentViewController = nil
                _ = delegates  // keep delegates alive until callback fires
            }
            primary.toggleFullScreen(nil)
        }
    }

    private func handleScreenParametersChanged() {
        guard !breakOverlayWindows.isEmpty else { return }
        // Rebuilding fullscreen windows mid-break would force two extra
        // Space transitions, which is more disruptive than a stale frame on
        // a freshly attached display. We accept the trade-off and only
        // rebuild on the next break.
    }

    // MARK: - Main menu (needed for ⌘Q and ⌘, to work on an .accessory app)

    private func setupMainMenu() {
        let main = NSMenu()

        let appMenuItem = NSMenuItem()
        main.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "Settings…",
                        action: #selector(openSettings),
                        keyEquivalent: ",").target = self
        appMenu.addItem(NSMenuItem.separator())
        addCheckForUpdatesItem(to: appMenu)
        appMenu.addItem(NSMenuItem.separator())
        // Hidden test shortcut: ⌘⌃⌥⇧T fast-forwards the current timer so the
        // end-of-phase UI can be exercised without waiting. Deliberately awkward
        // (all four modifiers) so it isn't hit accidentally.
        let fastForwardItem = NSMenuItem(title: "Fast-forward timer (test)",
                                         action: #selector(menuFastForward),
                                         keyEquivalent: "t")
        fastForwardItem.keyEquivalentModifierMask = [.command, .control, .option, .shift]
        fastForwardItem.target = self
        appMenu.addItem(fastForwardItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Dynamic Pomodoro",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        NSApp.mainMenu = main
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = BundleResource.image(forResource: "DolphinTemplate")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeft
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Open", action: #selector(openMainWindow), keyEquivalent: "o").target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Start focus", action: #selector(menuStartFocus), keyEquivalent: "s").target = self
        menu.addItem(withTitle: "Abandon session", action: #selector(menuAbandon), keyEquivalent: "").target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(NSMenuItem.separator())
        addCheckForUpdatesItem(to: menu)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        updateStatusItemTitle()
    }

    private func updateStatusItemTitle() {
        guard let button = statusItem?.button else { return }
        let formatted = timer.remainingFormatted
        let text = switch timer.phase {
        case .idle: ""
        case .focus: " F \(formatted)"
        case .breakRunning: " B \(formatted)"
        }
        // Tabular (monospaced) digits so each tick doesn't change the title's
        // width — otherwise the variable-length status item resizes and the
        // dolphin icon visibly shifts left/right in the menu bar.
        let font = NSFont.menuBarFont(ofSize: 0)
        let monospacedDigitFont = NSFont.monospacedDigitSystemFont(
            ofSize: font.pointSize,
            weight: .regular
        )
        button.attributedTitle = NSAttributedString(
            string: text,
            attributes: [.font: monospacedDigitFont]
        )
    }

    // MARK: - Windows

    @objc private func openMainWindow() {
        open(window: &mainWindow,
             title: "Dynamic Pomodoro",
             size: NSSize(width: 560, height: 520),
             styleMask: [.titled, .closable, .miniaturizable],
             delegate: MainWindowDelegate.shared) {
            NSHostingController(rootView: MainWindowView(timer: self.timer))
        }
    }

    @objc private func openSettings() {
        open(window: &settingsWindow,
             title: "Settings",
             size: NSSize(width: 380, height: 280),
             styleMask: [.titled, .closable]) {
            NSHostingController(rootView: SettingsView(settings: self.settings))
        }
    }

    private func open(
        window windowRef: inout NSWindow?,
        title: String,
        size: NSSize,
        styleMask: NSWindow.StyleMask,
        delegate: NSWindowDelegate? = nil,
        makeController: () -> NSViewController
    ) {
        if let w = windowRef {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentViewController: makeController())
        window.title = title
        window.styleMask = styleMask
        window.setContentSize(size)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        windowRef = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Menu actions

    @objc private func menuStartFocus() {
        if case .idle = timer.phase { timer.startFocus() }
        openMainWindow()
    }

    @objc private func menuAbandon() {
        if case .focus = timer.phase { timer.abandonFocus() }
    }

    @objc private func menuFastForward() {
        timer.fastForward()
    }

    /// Point the menu item at Sparkle's controller so its built-in
    /// `validateMenuItem:` greys the item out while a check is in flight.
    /// When the controller is nil (no bundle, i.e. `swift run`), fall back to
    /// the wrapper's no-op forwarder so the menu still validates.
    private func addCheckForUpdatesItem(to menu: NSMenu) {
        let item = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        if let controller = updater.controller {
            item.target = controller
        } else {
            item.target = updater
            item.action = #selector(UpdaterService.checkForUpdates(_:))
        }
        menu.addItem(item)
    }
}

/// Keeps the main window hidden (rather than destroyed) when the user closes it —
/// the app stays alive via the menu bar.
final class MainWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = MainWindowDelegate()
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

/// Hosts a single break overlay (one per display). Owns its own native
/// fullscreen Space so the overlay covers other apps' fullscreen windows on
/// the same display.
private final class BreakWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Per-window delegate for break overlays. Each break window owns one so
/// `AppDelegate` can chain fullscreen-entry across displays and react to
/// exits per-window. Callbacks are *one-shot*: each fires on the next
/// matching transition and then clears, which keeps the watchdog's
/// recovery re-toggles from re-triggering setup logic that has already run.
/// AppKit invokes these on the main thread, so we hop straight into
/// `@MainActor` work without a thread switch.
private final class BreakWindowDelegate: NSObject, NSWindowDelegate {
    var onNextEnterFullScreen: (@MainActor () -> Void)?
    var onNextExitFullScreen: (@MainActor () -> Void)?

    func windowDidEnterFullScreen(_ notification: Notification) {
        let callback = onNextEnterFullScreen
        onNextEnterFullScreen = nil
        MainActor.assumeIsolated { callback?() }
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        let callback = onNextExitFullScreen
        onNextExitFullScreen = nil
        MainActor.assumeIsolated { callback?() }
    }
}

// MARK: - Bootstrap

@MainActor
private func bootstrap() {
    let app = NSApplication.shared
    _bootstrapDelegate = AppDelegate()
    app.delegate = _bootstrapDelegate
    app.run()
}

nonisolated(unsafe) private var _bootstrapDelegate: AppDelegate?

MainActor.assumeIsolated { bootstrap() }
