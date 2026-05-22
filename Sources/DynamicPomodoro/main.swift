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
        breakOverlayWindows = NSScreen.screens.map {
            makeBreakOverlayPanel(for: $0, isPrimary: $0 == primaryScreen)
        }

        NSApp.activate(ignoringOtherApps: true)
        for window in breakOverlayWindows {
            window.alphaValue = fadeIn ? 0 : 1
            if window.contentViewController == nil { window.orderFrontRegardless() }
        }
        breakOverlayWindows.first(where: { $0.contentViewController != nil })?.makeKeyAndOrderFront(nil)

        guard fadeIn else { return }
        NSApp.requestUserAttention(.informationalRequest)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 4.0
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            breakOverlayWindows.forEach { $0.animator().alphaValue = 1.0 }
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
        breakOverlayWindows.forEach { $0.orderOut(nil) }
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
        let formatted = timer.state.remainingFormatted
        let text = switch timer.state.phase {
        case .idle: ""
        case .focus: " F \(formatted)"
        case .breakRunning: " B \(formatted)"
        }
        // Tabular (monospaced) digits so each tick doesn't change the title's
        // width — otherwise the variable-length status item resizes and the
        // dolphin icon visibly shifts left/right in the menu bar.
        let monospacedDigitFont = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.menuBarFont(ofSize: 0).pointSize,
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
        if case .idle = timer.state.phase { timer.startFocus() }
        openMainWindow()
    }

    @objc private func menuAbandon() {
        if case .focus = timer.state.phase { timer.abandonFocus() }
    }

    @objc private func menuFastForward() {
        timer.fastForward()
    }

    /// Point the menu item at Sparkle's controller so its built-in
    /// `validateMenuItem:` greys the item out while a check is in flight.
    /// Absent in `swift run` (no bundle, no controller).
    private func addCheckForUpdatesItem(to menu: NSMenu) {
        guard let controller = updater.controller else { return }
        let item = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        item.target = controller
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
