import AppKit
import Combine
import SwiftUI
#if canImport(Sparkle)
import Sparkle
#endif

// Entry point. Uses AppKit directly (rather than SwiftUI's @main App + MenuBarExtra)
// so this builds as a plain SPM executable — no Xcode project or app bundle required.
// Trade-off: we wire menu bar + windows by hand, but gain `swift run` portability.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings.shared
    private let timer = TimerEngine()
    private let notifications = NotificationService.shared
    private let updater = UpdaterService.shared

    private var statusItem: NSStatusItem!
    /// Held so the countdown and the idle click can detach it (a click
    /// cancels/starts instead of opening "Open"/"Start focus"/etc) and
    /// reattach it once the countdown ends or the phase leaves idle.
    private var statusMenu: NSMenu!
    /// Hidden except during `.breakPending` (SPEC_LOOP_CONTINUITY.md §4.3).
    private var startBreakNowItem: NSMenuItem!
    /// Hidden except during `.focus` — same level-triggered treatment as
    /// `startBreakNowItem`, for the same reason: an action with no meaning
    /// in the current phase shouldn't be sitting there greyed out.
    private var abandonItem: NSMenuItem!
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var statsWindow: NSWindow?
    private lazy var overlayManager = BreakOverlayManager(timer: timer)
    private lazy var autoStart = AutoStartService(timer: timer)
    private lazy var screenLockMonitor = ScreenLockMonitor()
    private var phaseCancellable: AnyCancellable?
    private var titleCancellable: AnyCancellable?
    private var countdownCancellable: AnyCancellable?
    private var settingsCancellable: AnyCancellable?
    /// Idle-only ticker so the menu-bar title's suggested duration stays
    /// accurate while idle (SPEC_LOOP_CONTINUITY.md §5.2) — created on
    /// entering `.idle`, invalidated on leaving it.
    private var idleTitleTicker: Timer?

    private lazy var menuBarFont = NSFont.monospacedDigitSystemFont(
        ofSize: NSFont.menuBarFont(ofSize: 0).pointSize,
        weight: .regular
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar app: no Dock icon, no app switcher entry. Matches the
        // installed bundle's LSUIElement and the README's promise; windows
        // are focused explicitly via activate(ignoringOtherApps:).
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()
        notifications.requestAuthorizationIfNeeded()
        setupStatusItem()

        // No window at launch (SPEC_LOOP_CONTINUITY.md §4.2) — the status
        // item already says "Start Nm" and one click starts it.

        wireEffectHooks()

        // Drive the menu-bar title straight from engine state — no second
        // timer, no idle wakeups, no beat drift against the engine tick.
        // @Published emits on willSet, so use the emitted value rather than
        // re-reading timer.state inside the sink.
        titleCancellable = timer.$state.sink { [weak self] newState in
            Task { @MainActor in self?.updateStatusItemTitle(for: newState) }
        }

        // Show/hide the full-screen break overlay, the "Start break now"
        // menu item, and the idle title ticker in response to phase changes.
        phaseCancellable = timer.$state
            .map(\.phase)
            .removeDuplicates(by: { $0.tag == $1.tag })
            .sink { [weak self] newPhase in
                Task { @MainActor in self?.handlePhaseChange(newPhase) }
            }

        // One function owns the status item's menu-vs-action mode
        // (SPEC_LOOP_CONTINUITY.md §5.3); both the phase sink above and this
        // countdown sink call into it rather than each reaching for
        // statusItem.menu independently.
        countdownCancellable = autoStart.$isCountingDown.sink { [weak self] _ in
            Task { @MainActor in self?.updateStatusItemMode() }
        }

        // The idle title is a function of Settings (min/max/workday all
        // move the curve) — recompute whenever any of them change, in
        // addition to the phase-driven recompute above.
        settingsCancellable = settings.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.updateStatusItemTitle(for: self.timer.state)
            }
        }

        // Same staleness seams IdleView already covers, for the same
        // reason: the idle title can otherwise go stale for up to the
        // ticker's 60s while nothing else prompts a recompute.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.updateStatusItemTitle(for: self.timer.state)
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.updateStatusItemTitle(for: self.timer.state)
            }
        }
    }

    /// Connects the reducer's three window/countdown effects, the unlock
    /// countdown's cancel path, and the screen-lock signal to the AppKit
    /// glue that interprets them. Kept separate from the Combine sinks below
    /// so the wiring reads as one block.
    private func wireEffectHooks() {
        timer.onOfferAutoStart = { [weak self] now in self?.autoStart.offerAfterSkip(now: now) }
        timer.onPresentMainWindow = { [weak self] in self?.presentMainWindow(requireUnlocked: true) }
        timer.onHideMainWindow = { [weak self] in self?.hideMainWindow() }

        autoStart.onCancelPresentsWindow = { [weak self] in self?.presentMainWindow(requireUnlocked: false) }

        screenLockMonitor.onUnlock = { [weak self] in self?.autoStart.handleUnlock() }
        screenLockMonitor.onLock = { [weak self] in self?.autoStart.handleLock() }
    }

    /// Quitting mid-break (or while one is owed) would be a one-keystroke,
    /// unlogged break skip — far cheaper than the sanctioned 15-second hold.
    /// The tool absorbs that decision (PURPOSE principle 4): finish the
    /// break or hold to skip, and quit works again the moment it's over.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        switch timer.state.phase {
        case .breakRunning, .breakPending: return .terminateCancel
        case .idle, .focus: return .terminateNow
        }
    }

    // MARK: - Main menu (needed for ⌘Q and ⌘, to work on an .accessory app)

    private func setupMainMenu() {
        let main = NSMenu()
        let appMenuItem = NSMenuItem()
        main.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        addSharedMenuTail(to: appMenu)
        #if DEBUG
        // Hidden test shortcut: ⌘⌃⌥⇧T fast-forwards the current timer so the
        // end-of-phase UI can be exercised without waiting. Debug builds only:
        // in a release build it would be a friction-free break skip that logs
        // a full breakCompleted, corrupting both the loop and the data.
        addItem("Fast-forward timer (test)", to: appMenu, action: #selector(menuFastForward),
                key: "t", modifiers: [.command, .control, .option, .shift])
        // Hidden test shortcut: exercises the unlock auto-start countdown
        // (SPEC_UNLOCK_AUTOSTART.md) without actually locking the screen.
        // Runs the identical gate + countdown path a real unlock would.
        addItem("Simulate unlock (test)", to: appMenu, action: #selector(menuSimulateUnlock),
                key: "u", modifiers: [.command, .control, .option, .shift])
        #endif
        appMenu.addItem(.separator())
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
            // Harmless in menu-attached mode (button.action is nil there);
            // needed so a right-click reaches the action in idle/countdown
            // mode (SPEC_LOOP_CONTINUITY.md §5.3) instead of only left-click.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let menu = NSMenu()
        menu.delegate = self
        addItem("Open", to: menu, action: #selector(openMainWindow), key: "o")
        addItem("Stats", to: menu, action: #selector(openStats), key: "")
        menu.addItem(.separator())
        addItem("Start focus", to: menu, action: #selector(menuStartFocus), key: "s")
        abandonItem = addItem(AbandonPrompt.menuTitle, to: menu, action: #selector(menuAbandonFocus))
        abandonItem.isHidden = true
        startBreakNowItem = addItem("Start break now", to: menu, action: #selector(menuStartBreakNow))
        startBreakNowItem.isHidden = true
        menu.addItem(.separator())
        addSharedMenuTail(to: menu)
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusMenu = menu

        updateStatusItemMode()
        updateStatusItemTitle(for: timer.state)
    }

    /// Reacts to every phase change: the full-screen break overlay, the
    /// visibility of the two phase-specific menu items ("Start break now",
    /// "Abandon session"), and the idle-only title ticker are all
    /// level-triggered off the current phase rather than edge-triggered off
    /// a specific transition.
    private func handlePhaseChange(_ phase: PomodoroState.Phase) {
        if case .breakRunning = phase { overlayManager.show() } else { overlayManager.hide() }

        if case .breakPending = phase {
            startBreakNowItem.isHidden = false
        } else {
            startBreakNowItem.isHidden = true
        }

        if case .focus = phase {
            abandonItem.isHidden = false
        } else {
            abandonItem.isHidden = true
        }

        if case .idle = phase {
            startIdleTitleTicker()
        } else {
            stopIdleTitleTicker()
        }

        updateStatusItemMode()
    }

    /// One function owns whether the status item shows its menu or acts as
    /// a button, so the countdown short-circuit and the idle click-to-start
    /// affordance compose instead of fighting over `statusItem.menu`
    /// (SPEC_LOOP_CONTINUITY.md §5.3). Precedence, highest first: a running
    /// countdown, then idle, then everything else (menu, as always).
    private func updateStatusItemMode() {
        guard let button = statusItem?.button else { return }
        if autoStart.isCountingDown {
            statusItem.menu = nil
            button.target = self
            button.action = #selector(statusItemCountdownClick)
        } else if case .idle = timer.state.phase {
            statusItem.menu = nil
            button.target = self
            button.action = #selector(statusItemIdleClick)
        } else {
            button.target = nil
            button.action = nil
            statusItem.menu = statusMenu
        }
    }

    /// Both left and right click cancel a running countdown — there's only
    /// one meaning available in this mode.
    @objc private func statusItemCountdownClick() {
        autoStart.cancelCountdown(suppress: true)
    }

    /// Left click starts the suggested session; right/control click opens
    /// the menu via the standard reattach-click-detach dance, matching what
    /// the countdown short-circuit already does for its own cancel click.
    @objc private func statusItemIdleClick() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            statusItem.menu = statusMenu
            statusItem.button?.performClick(nil)
            // `menuDidClose` detaches the menu again once it's dismissed.
        } else {
            timer.startFocus()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        updateStatusItemMode()
    }

    /// Settings + separator + Check for Updates + separator — appears in both the app menu and the status menu.
    private func addSharedMenuTail(to menu: NSMenu) {
        addItem("Settings…", to: menu, action: #selector(openSettings), key: ",")
        menu.addItem(.separator())
        addCheckForUpdatesItem(to: menu)
        menu.addItem(.separator())
    }

    /// App-specific menu items only — Quit-style responder-chain items use addItem(withTitle:) directly.
    @discardableResult
    private func addItem(
        _ title: String,
        to menu: NSMenu,
        action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    private func updateStatusItemTitle(for state: PomodoroState) {
        guard let button = statusItem?.button else { return }
        let text = MenuBarTitle.text(for: state, suggestedMinutes: timer.suggestedFocusMinutes())
        // Tabular (monospaced) digits so each tick doesn't change the title's
        // width — otherwise the variable-length status item resizes and the
        // dolphin icon visibly shifts left/right in the menu bar.
        button.attributedTitle = NSAttributedString(string: text, attributes: [.font: menuBarFont])
    }

    /// The idle title is a live function of `Date()` (the curve moves
    /// continuously), but `timer.$state` never emits while idle — so
    /// without this, the title would freeze at whatever the curve said when
    /// the last break ended. A generous tolerance lets macOS coalesce the
    /// wakeup; this timer does not exist outside `.idle` (§5.2).
    private func startIdleTitleTicker() {
        stopIdleTitleTicker()
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.updateStatusItemTitle(for: self.timer.state) }
        }
        t.tolerance = 15
        RunLoop.main.add(t, forMode: .common)
        idleTitleTicker = t
    }

    private func stopIdleTitleTicker() {
        idleTitleTicker?.invalidate()
        idleTitleTicker = nil
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

    /// Gated opening for the two app-initiated windows (SPEC_LOOP_CONTINUITY.md
    /// §4.2): a break ending unlocked (`requireUnlocked: true`, F2+F3) and a
    /// cancelled countdown (`requireUnlocked: false`, F3 only — the cancel
    /// itself is proof enough of presence). "Open" from the menu bypasses
    /// this entirely and is never suppressed, not even during a call.
    private func presentMainWindow(requireUnlocked: Bool) {
        guard !CallDetectionService.isOnCall() else { return }
        if requireUnlocked && screenLockMonitor.state != .unlocked { return }
        openMainWindow()
    }

    private func hideMainWindow() {
        mainWindow?.orderOut(nil)
    }

    /// Its own window, not a phase in the main one: the main window hides
    /// itself during focus (§4.2) and a read-out that disappears the moment
    /// you start working would be useless.
    @objc private func openStats() {
        open(window: &statsWindow,
             title: "Stats",
             size: NSSize(width: 620, height: 460),
             styleMask: [.titled, .closable, .miniaturizable]) {
            NSHostingController(rootView: StatsView(log: SessionLogStore.shared))
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
        defer { NSApp.activate(ignoringOtherApps: true) }
        if let w = windowRef {
            w.makeKeyAndOrderFront(nil)
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
    }

    // MARK: - Menu actions

    @objc private func menuStartFocus() {
        if case .idle = timer.state.phase { timer.startFocus() }
    }

    @objc private func menuStartBreakNow() {
        timer.startPendingBreak()
    }

    /// The same discard the in-window button performs, reachable without
    /// opening a window — which matters because §4.2 keeps the main window
    /// hidden for the whole of a focus session, so until now the only way
    /// to abandon one was to go and open it.
    ///
    /// Confirmed, for the reason spelled out on `AbandonPrompt`. Guarded on
    /// both sides of the modal: the session can hit its own deadline while
    /// the alert is up, and abandoning a break that has since started would
    /// be a silent, unlogged break skip.
    @objc private func menuAbandonFocus() {
        guard case .focus = timer.state.phase else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = AbandonPrompt.title
        alert.informativeText = AbandonPrompt.message
        // "Continue" first, so it takes the default (rightmost, Return) slot:
        // a stray Return on this alert must not discard the session.
        alert.addButton(withTitle: AbandonPrompt.cancel)
        alert.addButton(withTitle: AbandonPrompt.confirm)
        alert.buttons.last?.hasDestructiveAction = true
        // An .accessory app isn't frontmost once the menu closes, so without
        // this the alert opens behind whatever the user is looking at.
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        guard case .focus = timer.state.phase else { return }
        timer.abandonFocus()
    }

    #if DEBUG
    @objc private func menuFastForward() {
        timer.fastForward()
    }

    @objc private func menuSimulateUnlock() {
        autoStart.handleUnlock()
    }
    #endif

    /// Point the menu item at Sparkle's controller so its built-in
    /// `validateMenuItem:` greys the item out while a check is in flight.
    /// Absent in `swift run` (no bundle, no controller) and in the
    /// no-AutoUpdate build variant (no Sparkle at all).
    private func addCheckForUpdatesItem(to menu: NSMenu) {
        #if canImport(Sparkle)
        guard let controller = updater.controller else { return }
        let item = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        item.target = controller
        menu.addItem(item)
        #endif
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

// MARK: - Bootstrap

#if DEBUG
// `swift run DynamicPomodoro rehearse [...]` prints a rehearsal transcript
// and exits without ever touching AppKit — the same entry point Linux
// reaches via its dedicated `swift run rehearse` executable (the app is the
// only executable product on macOS so that plain `swift run` keeps working).
// DEBUG-only, like every other test seam in this codebase.
if CommandLine.arguments.dropFirst().first == "rehearse" {
    exit(RehearsalCLI.run(arguments: Array(CommandLine.arguments.dropFirst(2))))
}
#endif

@MainActor
private func bootstrap() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // NSApplication.delegate is unretained; run() never returns, so this
    // stack frame keeps the delegate alive for the app's lifetime.
    withExtendedLifetime(delegate) { app.run() }
}

MainActor.assumeIsolated { bootstrap() }
