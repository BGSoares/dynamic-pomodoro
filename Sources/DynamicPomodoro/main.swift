import AppKit
import Combine
import SwiftUI

// Entry point. Uses AppKit directly (rather than SwiftUI's @main App + MenuBarExtra)
// so this builds as a plain SPM executable — no Xcode project or app bundle required.
// Trade-off: we wire menu bar + windows by hand, but gain `swift run` portability.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings.shared
    private let timer = TimerController()
    private let notifications = NotificationService.shared

    private var statusItem: NSStatusItem!
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var breakOverlayWindows: [NSWindow] = []
    private var menuObservation: Any?
    private var phaseCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupMainMenu()
        notifications.requestAuthorizationIfNeeded()
        setupStatusItem()

        // Always open the main window on launch.
        openMainWindow()

        // Keep the menu bar title live-updating.
        menuObservation = NotificationCenter.default.addObserver(
            forName: .init("PomodoroStateChanged"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateStatusItemTitle() }
        }

        // Drive title refresh once per second — cheap, and independent of the TimerController internals.
        // Scheduled in `.common` modes so it keeps firing during event tracking
        // (e.g. while the user holds the skip button).
        let titleTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateStatusItemTitle() }
        }
        RunLoop.main.add(titleTimer, forMode: .common)

        // Show/hide the full-screen break overlay in response to phase changes.
        phaseCancellable = timer.$phase
            .removeDuplicates()
            .sink { [weak self] newPhase in
                Task { @MainActor in self?.handlePhaseChange(newPhase) }
            }
    }

    // MARK: - Break overlay

    private func handlePhaseChange(_ phase: TimerController.Phase) {
        switch phase {
        case .breakRunning:
            showBreakOverlay()
        case .idle, .focus:
            hideBreakOverlay()
        }
    }

    private func showBreakOverlay() {
        if breakOverlayWindows.isEmpty {
            // One panel per connected display. Only the primary panel hosts the
            // SwiftUI timer/controls; the rest are pure black blockers so the
            // user can't sneak work onto a secondary screen during a break.
            let primaryScreen = NSScreen.main ?? NSScreen.screens.first
            for screen in NSScreen.screens {
                let isPrimary = (screen == primaryScreen)
                breakOverlayWindows.append(makeBreakOverlayPanel(for: screen, isPrimary: isPrimary))
            }
        }

        guard !breakOverlayWindows.isEmpty else { return }

        // Fade in slowly — the fade IS the prep.
        // Activate the app so SwiftUI gestures (hold-to-skip) receive events.
        NSApp.activate(ignoringOtherApps: true)
        for window in breakOverlayWindows {
            window.alphaValue = 0
            if window.contentViewController == nil {
                // Secondary blockers shouldn't steal key status from the primary.
                window.orderFrontRegardless()
            }
        }
        // Order the primary last so it ends up as the key window for gestures.
        if let primary = breakOverlayWindows.first(where: { $0.contentViewController != nil }) {
            primary.makeKeyAndOrderFront(nil)
        }
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
        // Use a borderless NSPanel so it can join all spaces and cover menu bar.
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        if isPrimary {
            panel.contentViewController = NSHostingController(rootView: BreakOverlayView(timer: timer))
            panel.ignoresMouseEvents = false
        } else {
            // Pure black blocker — no UI, no event handling.
            panel.ignoresMouseEvents = true
        }
        panel.level = .screenSaver
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
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 1.5
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for window in windows {
                window.animator().alphaValue = 0
            }
        }, completionHandler: { [weak self] in
            for window in windows {
                window.orderOut(nil)
            }
            // Clear so the next break rebuilds against the current screen set —
            // handles dock/undock between breaks without a screen-change observer.
            Task { @MainActor in self?.breakOverlayWindows.removeAll() }
        })
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
        let formatted = settings.compactMenuBarTimer
            ? timer.remainingFormattedCompact
            : timer.remainingFormatted
        let text: String
        switch timer.phase {
        case .idle:
            text = ""
        case .focus:
            text = " F \(formatted)"
        case .breakRunning:
            text = " B \(formatted)"
        }
        // Use tabular (monospaced) digits so each second's tick doesn't change
        // the title's width — otherwise the variable-length status item resizes
        // and the dolphin icon visibly shifts left/right in the menu bar.
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
        let root = MainWindowView(timer: timer, settings: settings)
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
        window.setContentSize(NSSize(width: 480, height: 600))
        window.center()
        window.isReleasedWhenClosed = false
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Menu actions

    @objc private func menuStartFocus() {
        if timer.phase == .idle { timer.startFocus() }
        openMainWindow()
    }

    @objc private func menuAbandon() {
        if timer.phase == .focus { timer.abandonFocus() }
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

// MARK: - Bootstrap

@MainActor
private func bootstrap() {
    let app = NSApplication.shared
    // Keep a strong reference so the delegate outlives this function.
    _bootstrapDelegate = AppDelegate()
    app.delegate = _bootstrapDelegate
    app.run()
}

nonisolated(unsafe) private var _bootstrapDelegate: AppDelegate?

MainActor.assumeIsolated { bootstrap() }
