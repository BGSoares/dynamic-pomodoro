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
    private lazy var overlayManager = BreakOverlayManager(timer: timer)
    private var phaseCancellable: AnyCancellable?
    private var titleCancellable: AnyCancellable?

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

        openMainWindow()

        // Drive the menu-bar title straight from engine state — no second
        // timer, no idle wakeups, no beat drift against the engine tick.
        // @Published emits on willSet, so use the emitted value rather than
        // re-reading timer.state inside the sink.
        titleCancellable = timer.$state.sink { [weak self] newState in
            Task { @MainActor in self?.updateStatusItemTitle(for: newState) }
        }

        // Show/hide the full-screen break overlay in response to phase changes.
        phaseCancellable = timer.$state
            .map(\.phase)
            .removeDuplicates(by: { $0.tag == $1.tag })
            .sink { [weak self] newPhase in
                guard let self else { return }
                Task { @MainActor in
                    if case .breakRunning = newPhase { self.overlayManager.show() } else { self.overlayManager.hide() }
                }
            }
    }

    /// Quitting mid-break would be a one-keystroke, unlogged break skip —
    /// far cheaper than the sanctioned 15-second hold. The tool absorbs that
    /// decision (PURPOSE principle 4): finish the break or hold to skip,
    /// and quit works again the moment the break is over.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if case .breakRunning = timer.state.phase { return .terminateCancel }
        return .terminateNow
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
        }

        let menu = NSMenu()
        addItem("Open", to: menu, action: #selector(openMainWindow), key: "o")
        menu.addItem(.separator())
        addItem("Start focus", to: menu, action: #selector(menuStartFocus), key: "s")
        menu.addItem(.separator())
        addSharedMenuTail(to: menu)
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        updateStatusItemTitle(for: timer.state)
    }

    /// Settings + separator + Check for Updates + separator — appears in both the app menu and the status menu.
    private func addSharedMenuTail(to menu: NSMenu) {
        addItem("Settings…", to: menu, action: #selector(openSettings), key: ",")
        menu.addItem(.separator())
        addCheckForUpdatesItem(to: menu)
        menu.addItem(.separator())
    }

    /// App-specific menu items only — Quit-style responder-chain items use addItem(withTitle:) directly.
    private func addItem(
        _ title: String,
        to menu: NSMenu,
        action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = .command
    ) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
    }

    private func updateStatusItemTitle(for state: PomodoroState) {
        guard let button = statusItem?.button else { return }
        let text = switch state.phase {
        case .idle: ""
        case .focus: " F \(state.remainingFormatted)"
        case .breakRunning: " B \(state.remainingFormatted)"
        }
        // Tabular (monospaced) digits so each tick doesn't change the title's
        // width — otherwise the variable-length status item resizes and the
        // dolphin icon visibly shifts left/right in the menu bar.
        button.attributedTitle = NSAttributedString(string: text, attributes: [.font: menuBarFont])
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
        openMainWindow()
    }

    #if DEBUG
    @objc private func menuFastForward() {
        timer.fastForward()
    }
    #endif

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

// MARK: - Bootstrap

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
