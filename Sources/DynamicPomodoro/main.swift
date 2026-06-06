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

    private lazy var menuBarFont = NSFont.monospacedDigitSystemFont(
        ofSize: NSFont.menuBarFont(ofSize: 0).pointSize,
        weight: .regular
    )

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
                Task { @MainActor in
                    guard let self else { return }
                    if case .breakRunning = newPhase { self.overlayManager.show() } else { self.overlayManager.hide() }
                }
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
        // Hidden test shortcut: ⌘⌃⌥⇧T fast-forwards the current timer so the
        // end-of-phase UI can be exercised without waiting. Deliberately awkward
        // (all four modifiers) so it isn't hit accidentally.
        addItem("Fast-forward timer (test)", to: appMenu, action: #selector(menuFastForward),
                key: "t", modifiers: [.command, .control, .option, .shift])
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
        addItem("Abandon session", to: menu, action: #selector(menuAbandon))
        menu.addItem(.separator())
        addSharedMenuTail(to: menu)
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        updateStatusItemTitle()
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
