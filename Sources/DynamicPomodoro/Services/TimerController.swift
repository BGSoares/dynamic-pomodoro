import Foundation
import Combine
import SwiftUI

/// Central state machine for the pomodoro loop.
///
/// States:
///   .idle          → no active session; idle screen
///   .focus         → focus timer running
///   .breakRunning  → break timer running (auto-starts when focus completes;
///                    the overlay's fade-in is the prep — no separate prompt)
///
/// A paused/abandoned focus session is discarded (§3.5) — no partial credit.
@MainActor
final class TimerController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case focus
        case breakRunning
    }

    // Published state
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var totalSeconds: Int = 0
    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var currentActivity: Activity?
    @Published private(set) var currentReminderMessage: String?
    /// Last focus duration (minutes) — drives break-duration calculation.
    @Published private(set) var lastFocusMinutes: Int = 0

    // Dependencies
    private let settings: Settings
    private let log: SessionLogStore
    private let library: [Activity]
    private let notifications: NotificationService
    private var rng = SystemRandomNumberGenerator()

    // Internal
    private var timer: Timer?
    private var phaseStart: Date?

    init(
        settings: Settings = .shared,
        log: SessionLogStore = .shared,
        library: [Activity] = ActivityLibrary.load(),
        notifications: NotificationService = .shared
    ) {
        self.settings = settings
        self.log = log
        self.library = library
        self.notifications = notifications
    }

    // MARK: - Focus

    /// Duration (minutes) the next focus session would be if started now.
    func suggestedFocusMinutes(now: Date = Date()) -> Int {
        DurationCurve.focusDuration(
            now: now,
            isFirstSessionOfDay: !log.hasEntryToday(now: now),
            settings: settings
        )
    }

    func startFocus(now: Date = Date()) {
        stopTimer()
        let minutes = suggestedFocusMinutes(now: now)
        lastFocusMinutes = minutes
        totalSeconds = minutes * 60
        remainingSeconds = totalSeconds
        phase = .focus
        phaseStart = now
        startTicker()

        notifications.notify(
            title: "Focus started",
            body: "\(minutes) min. Let's go.",
            playSound: settings.soundEnabled
        )
    }

    /// Abandon the current focus session — discarded, no partial credit (§3.5).
    func abandonFocus(now: Date = Date()) {
        guard phase == .focus else { return }
        if let start = phaseStart {
            log.append(SessionLogEntry(
                kind: .focusAbandoned,
                startedAt: start,
                endedAt: now,
                plannedMinutes: lastFocusMinutes,
                activityID: nil
            ))
        }
        stopTimer()
        phase = .idle
        remainingSeconds = 0
        totalSeconds = 0
    }

    private func completeFocus(now: Date = Date()) {
        guard phase == .focus else { return }
        if let start = phaseStart {
            log.append(SessionLogEntry(
                kind: .focusCompleted,
                startedAt: start,
                endedAt: now,
                plannedMinutes: lastFocusMinutes,
                activityID: nil
            ))
        }
        stopTimer()
        SoundService.focusComplete(enabled: settings.soundEnabled)
        startBreak(now: now)

        notifications.notify(
            title: "Focus complete",
            body: "Time for a break.",
            playSound: settings.soundEnabled
        )
    }

    // MARK: - Break

    /// Transition from focus → break. The overlay's fade-in is the prep; no separate prompt.
    private func startBreak(now: Date) {
        let breakMinutes = BreakLogic.breakDuration(forFocusMinutes: lastFocusMinutes)
        totalSeconds = breakMinutes * 60
        remainingSeconds = totalSeconds

        selectActivity(now: now)

        // Reminder message rule (§4.5): only on first break of day, or after a skipped break.
        let isFirstBreakToday = !log.hasBreakEntryToday(now: now)
        let lastWasSkip = log.lastBreakWasSkipped()
        if isFirstBreakToday || lastWasSkip {
            currentReminderMessage = ReminderMessages.random(excluding: nil, rng: &rng)
        } else {
            currentReminderMessage = nil
        }

        phase = .breakRunning
        phaseStart = now
        startTicker()
    }

    private func selectActivity(now: Date) {
        currentActivity = ActivitySelector.select(
            from: library,
            breakMinutes: totalSeconds / 60,
            now: now,
            recentActivityIDs: log.recentBreakActivityIDs(),
            lastCategory: log.lastBreakCategory(library: library),
            disabledCategories: settings.disabledCategories,
            settings: settings,
            rng: &rng
        )
    }

    /// Swap to a different activity without changing the break timer.
    func swapActivity(now: Date = Date()) {
        guard phase == .breakRunning else { return }
        let currentID = currentActivity?.id
        // Simple swap: re-run selection, excluding the current activity.
        let filtered = library.filter { $0.id != currentID }
        let pick = ActivitySelector.select(
            from: filtered,
            breakMinutes: totalSeconds / 60,
            now: now,
            recentActivityIDs: log.recentBreakActivityIDs(),
            lastCategory: log.lastBreakCategory(library: library),
            disabledCategories: settings.disabledCategories,
            settings: settings,
            rng: &rng
        )
        if let pick { currentActivity = pick }
    }

    func skipBreak(now: Date = Date()) {
        guard phase == .breakRunning else { return }
        log.append(SessionLogEntry(
            kind: .breakSkipped,
            startedAt: phaseStart ?? now,
            endedAt: now,
            plannedMinutes: totalSeconds / 60,
            activityID: currentActivity?.id
        ))
        stopTimer()
        phase = .idle
        remainingSeconds = 0
        totalSeconds = 0
        currentActivity = nil
        currentReminderMessage = nil
    }

    private func completeBreak(now: Date = Date()) {
        log.append(SessionLogEntry(
            kind: .breakCompleted,
            startedAt: phaseStart ?? now,
            endedAt: now,
            plannedMinutes: totalSeconds / 60,
            activityID: currentActivity?.id
        ))
        stopTimer()
        phase = .idle
        remainingSeconds = 0
        totalSeconds = 0
        currentActivity = nil
        currentReminderMessage = nil

        SoundService.breakComplete(enabled: settings.soundEnabled)
        notifications.notify(
            title: "Break complete",
            body: "Ready when you are.",
            playSound: settings.soundEnabled
        )
    }

    // MARK: - Ticker

    private func startTicker() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard remainingSeconds > 0 else {
            switch phase {
            case .focus: completeFocus()
            case .breakRunning: completeBreak()
            default: stopTimer()
            }
            return
        }
        remainingSeconds -= 1
    }

    // MARK: - Display helpers

    var remainingFormatted: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return 1.0 - Double(remainingSeconds) / Double(totalSeconds)
    }
}
