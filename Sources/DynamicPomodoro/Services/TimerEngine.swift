import Foundation
import Combine
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// ObservableObject shell around the pure `PomodoroReducer`.
///
/// - Owns the `PomodoroState` (`@Published`) so SwiftUI re-renders on every change.
/// - Dispatches `PomodoroAction`s into the reducer.
/// - Interprets the returned `[PomodoroEffect]` (notifications, log writes,
///   chimes, ticker start/stop, screen lock).
/// - Drives a 1s ticker while a phase is running.
/// - Re-ticks on wake from system sleep so a phase whose deadline elapsed
///   during sleep transitions promptly.
@MainActor
final class TimerEngine: ObservableObject {
    @Published private(set) var state = PomodoroState()

    private let settings: Settings
    private let log: SessionLogStore
    private let notifications: NotificationService
    private let library: [Activity]
    private var rng = SystemRandomNumberGenerator()

    private var ticker: Timer?
    private var wakeObserver: NSObjectProtocol?

    init(
        settings: Settings = .shared,
        log: SessionLogStore = .shared,
        notifications: NotificationService = .shared,
        library: [Activity] = Activity.defaultLibrary
    ) {
        self.settings = settings
        self.log = log
        self.notifications = notifications
        self.library = library

        #if canImport(AppKit)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.dispatch(.tick(now: Date())) }
        }
        #endif
    }

    deinit {
        #if canImport(AppKit)
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        #endif
    }

    // MARK: - Public actions

    func startFocus(now: Date = Date()) { dispatch(.startFocus(now: now)) }
    func abandonFocus(now: Date = Date()) { dispatch(.abandonFocus(now: now)) }
    func skipBreak(now: Date = Date()) { dispatch(.skipBreak(now: now)) }
    func fastForward(now: Date = Date()) { dispatch(.fastForward(now: now)) }

    // MARK: - Read helpers used by IdleView

    func suggestedFocusMinutes(now: Date = Date()) -> Int {
        DurationCurve.focusDuration(
            now: now,
            isFirstSessionOfDay: !log.hasEntryToday(now: now),
            settings: settings
        )
    }

    func dailyStats(now: Date = Date()) -> DailyStats {
        log.dailyStats(now: now)
    }

    // MARK: - Dispatch + effect interpretation

    private func dispatch(_ action: PomodoroAction) {
        let effects = PomodoroReducer.reduce(
            &state,
            action,
            settings: settings,
            log: log,
            library: library,
            rng: &rng
        )
        for effect in effects { run(effect) }
    }

    private func run(_ effect: PomodoroEffect) {
        switch effect {
        case .notify(let title, let body):
            notifications.notify(title: title, body: body)
        case .logSession(let entry):
            log.append(entry)
        case .playFocusCompleteChime:
            SoundService.focusComplete()
        case .playBreakCompleteChime:
            SoundService.breakComplete()
        case .startTicker:
            startTicker()
        case .stopTicker:
            stopTicker()
        case .lockScreen:
            ScreenLockService.lockScreen()
        }
    }

    // MARK: - Ticker

    private func startTicker() {
        ticker?.invalidate()
        // Scheduled in `.common` modes so the timer keeps firing during a
        // modal event-tracking loop (e.g. while the user holds the skip
        // button) — `.default` alone pauses during event tracking.
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.dispatch(.tick(now: Date())) }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}
