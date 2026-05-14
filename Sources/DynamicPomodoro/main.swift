import AppKit
import Combine
import SwiftUI

// Entry point. Uses AppKit directly (rather than SwiftUI's @main App + MenuBarExtra)
// so this builds as a plain SPM executable — no Xcode project or app bundle required.
// Trade-off: we wire menu bar + windows by hand, but gain `swift run` portability.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings.shared
    private let timer = TimerEngine()
    private let notifications = NotificationService.shared

    private var statusItem: NSStatusItem!
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var breakOverlayWindows: [NSWindow] = []
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
            .removeDuplicates(by: { Self.sameCase($0, $1) })
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

    /// Phase enums hold associated values that change per tick (deadlines).
    /// For the overlay show/hide decision, only the case matters.
    private static func sameCase(_ a: PomodoroState.Phase, _ b: PomodoroState.Phase) -> Bool {
        switch (a, b) {
        case (.idle, .idle), (.focus, .focus), (.breakRunning, .breakRunning):
            return true
        default:
            return false
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

    /// Build one panel per connected display and bring them on screen.
    /// Primary panel hosts the SwiftUI timer/controls; the rest are pure black
    /// blockers so the user can't sneak work onto a secondary screen during a
    /// break. Primary is picked by cursor location so the timer lands on the
    /// screen the user is actually looking at — `NSScreen.main` returns the
    /// screen with the key window, often a different display.
    /// `fadeIn` is true at break start (the 4 s fade IS the prep) and false
    /// when rebuilding mid-break for a display change (we're already running).
    private func showBreakOverlay(fadeIn: Bool = true) {
        let primaryScreen = currentBreakScreen()
        for screen in NSScreen.screens {
            let isPrimary = (screen == primaryScreen)
            breakOverlayWindows.append(makeBreakOverlayPanel(for: screen, isPrimary: isPrimary))
        }

        NSApp.activate(ignoringOtherApps: true)
        for window in breakOverlayWindows {
            window.alphaValue = fadeIn ? 0 : 1
            if window.contentViewController == nil {
                window.orderFrontRegardless()
            }
        }
        if let primary = breakOverlayWindows.first(where: { $0.contentViewController != nil }) {
            primary.makeKeyAndOrderFront(nil)
        }

        guard fadeIn else { return }
        NSApp.requestUserAttention(.informationalRequest)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 4.0
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for window in breakOverlayWindows {
                window.animator().alphaValue = 1.0
            }
        }
    }

    private func makeBreakOverlayPanel(for screen: NSScreen, isPrimary: Bool) -> NSPanel {
        let frame = screen.frame
        let panel = KeyablePanel(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        if isPrimary {
            panel.contentViewController = NSHostingController(rootView: BreakOverlayView(timer: timer))
            panel.ignoresMouseEvents = false
        } else {
            panel.ignoresMouseEvents = true
        }
        // Shielding level (the one macOS uses for the lock-screen shield) sits above
        // native fullscreen apps. `.screenSaver` is too low on modern macOS — apps
        // in their own fullscreen Space punch through it.
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.alphaValue = 0
        panel.setFrame(frame, display: false)
        return panel
    }

    private func hideBreakOverlay() {
        let windows = breakOverlayWindows
        guard windows.contains(where: { $0.isVisible }) else { return }
        // Clear synchronously so a screen-change racing with this fade-out
        // doesn't see a stale array and rebuild on top of windows we're
        // tearing down. The animation owns its captured `windows` snapshot.
        breakOverlayWindows.removeAll()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 1.5
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for window in windows {
                window.animator().alphaValue = 0
            }
        }, completionHandler: {
            for window in windows {
                window.orderOut(nil)
            }
        })
    }

    private func handleScreenParametersChanged() {
        guard breakOverlayWindows.contains(where: { $0.isVisible }) else { return }
        for window in breakOverlayWindows {
            window.orderOut(nil)
        }
        breakOverlayWindows.removeAll()
        showBreakOverlay(fadeIn: false)
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
            let image = Bundle.module.image(forResource: "DolphinTemplate")
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
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        updateStatusItemTitle()
    }

    private func updateStatusItemTitle() {
        guard let button = statusItem?.button else { return }
        let formatted = timer.remainingFormatted
        let text: String
        switch timer.phase {
        case .idle:
            text = ""
        case .focus:
            text = " F \(formatted)"
        case .breakRunning:
            text = " B \(formatted)"
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
        if let w = mainWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = MainWindowView(timer: timer)
        let controller = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: controller)
        window.title = "Dynamic Pomodoro"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 560, height: 520))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = MainWindowDelegate.shared
        mainWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettings() {
        if let w = settingsWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = SettingsView(settings: settings)
        let controller = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: controller)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 380, height: 280))
        window.center()
        window.isReleasedWhenClosed = false
        settingsWindow = window
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

/// Borderless panels are non-key by default. Opt in so SwiftUI gestures and
/// any future keyboard shortcuts route correctly through the responder chain.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
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
