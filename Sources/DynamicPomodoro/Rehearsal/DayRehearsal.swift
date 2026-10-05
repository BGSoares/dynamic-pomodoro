import Foundation

/// Plays one full simulated workday through the real production logic —
/// `PomodoroReducer`, `ActivitySelector`, `DurationCurve`,
/// `ReminderMessages`, `UnlockGate`, the real `activities.json` — with a
/// synthetic clock, a scripted user, and a seeded RNG, and writes down
/// everything that user would have seen or heard.
///
/// What is real here: every decision. What is mirrored here: the thin AppKit
/// glue that interprets those decisions (`TimerEngine`'s effect loop,
/// `AppDelegate.handlePhaseChange`, `AutoStartService`'s countdown,
/// `ScreenLockMonitor`'s lock state) — each mirror is marked with the file
/// it mirrors, and changing that glue means changing its mirror here.
/// Pixels, chime audio and the physical screen lock are the only things a
/// rehearsal cannot vouch for; macOS CI compiles them and a compressed-time
/// run (`DP_SECONDS_PER_MINUTE`) shows them for real.
///
/// While it plays, it checks the invariants — the promises PURPOSE makes —
/// and records a finding for every violation. A finding is a bug the user
/// would have met.
final class DayRehearsal {
    struct Result {
        let script: RehearsalScript
        let seed: UInt64
        let header: [String]
        let events: [TranscriptEvent]
        let findings: [String]
        let entries: [SessionLogEntry]
        let calendar: Calendar

        func renderedTranscript() -> String {
            TranscriptRenderer.render(header: header, events: events, findings: findings, calendar: calendar)
        }
    }

    static func run(script: RehearsalScript, seed: UInt64 = 1) -> Result {
        let rehearsal = DayRehearsal(script: script, seed: seed)
        return rehearsal.play()
    }

    // MARK: - Fixed world

    private let script: RehearsalScript
    private let seed: UInt64
    /// The rehearsal's own calendar — UTC Gregorian, so the same script and
    /// seed produce the same transcript on any machine in any time zone.
    private let calendar: Calendar
    private let settings: Settings
    private let defaults: UserDefaults
    private let suiteName: String
    private let store: SessionLogStore
    private let storeDir: URL
    private let library: [Activity]
    private var rng: SeededRNG

    // MARK: - Mutable world

    private var clock: Date
    private var state = PomodoroState()
    private var tickerRunning = false                    // mirrors TimerEngine.startTicker/stopTicker
    private var screen: ScreenLockState = .unknown       // mirrors ScreenLockMonitor.state
    private var mainWindowVisible = false
    private var onCall = false
    private var asleepUntil: Date?

    // Countdown, mirroring AutoStartService.
    private var countdownDeadline: Date?
    private var countdownBreakEnd: Date?
    private var suppressedBreakEnd: Date?
    private var countdownOrdinal = 0

    // Persona intents.
    private var nextStartAt: Date?
    private var unlockAt: Date?
    private var unlockCount = 0
    private var holdSkipAt: Date?          // when the press begins
    private var holdCompletesAt: Date?
    private var doneForToday = false

    /// `Phase.tag` of `.breakRunning` — cases with associated values can't
    /// be named without a payload, so the discriminator is spelled here once.
    private let breakRunningTag = 3

    // Bookkeeping for triggers and invariants.
    private var breakOrdinal = 0
    private var pendingOpsFired = Set<Int>()
    private var lastPhaseTag: Int = PomodoroState.Phase.idle.tag
    private var lastMenuBarText = ""
    private var lastMenuBarPhaseTag: Int = PomodoroState.Phase.idle.tag
    private var sleptDuringBreak = false
    private var breakStartedManuallyAt: Date?
    private var breakLockedAt: Date?
    private var lastUserActionAt: Date?
    private var events: [TranscriptEvent] = []
    private var findings: [String] = []

    private init(script: RehearsalScript, seed: UInt64) {
        self.script = script
        self.seed = seed

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.locale = Locale(identifier: "en_US_POSIX")
        self.calendar = cal

        suiteName = "DayRehearsal-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        let s = Settings(defaults: defaults)
        s.workdayStartMinutes = script.workdayStartMinutes
        s.workdayEndMinutes = script.workdayEndMinutes
        s.minFocusStartMinutes = script.minFocusStartMinutes
        s.minFocusEndMinutes = script.minFocusEndMinutes
        s.maxFocusMinutes = script.maxFocusMinutes
        s.autoStartCountdownSeconds = script.autoStartCountdownSeconds
        s.autoStartWindowMinutes = script.autoStartWindowMinutes
        settings = s

        storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayRehearsal-\(UUID().uuidString)", isDirectory: true)
        store = SessionLogStore(directory: storeDir)
        library = Activity.defaultLibrary
        rng = SeededRNG(seed: seed)

        var comps = DateComponents()
        comps.year = script.year; comps.month = script.month; comps.day = script.day
        comps.hour = script.workdayStartMinutes / 60
        comps.minute = script.workdayStartMinutes % 60
        clock = cal.date(from: comps)!
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: storeDir)
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - The day

    private func play() -> Result {
        precondition(!TimeScale.isCompressed,
                     "rehearsals run on their own synthetic clock; unset DP_SECONDS_PER_MINUTE")
        defer { cleanUp() }

        if library.isEmpty {
            finding("activities.json failed to load — every break would fall back to the stub card")
        }

        // Arrival: sitting down IS the morning unlock, which is how the
        // ScreenLockMonitor first learns the screen state (it launches .unknown).
        env("you sit down and unlock the machine — the workday starts")
        performUnlock()
        refreshMenuBar()
        scheduleNextStart()

        let dayEnd = date(minute: script.workdayEndMinutes)
        let hardStop = date(minute: 23 * 60 + 59)

        while clock < hardStop {
            stepOneSecond()
            let idleAndQuiet = state.phase.isIdle
                && countdownDeadline == nil && asleepUntil == nil
            if clock >= dayEnd && idleAndQuiet { break }
        }
        if clock >= hardStop {
            finding("the day never settled back to idle by 23:59 — something is stuck")
        }

        env("end of workday — you close the laptop")
        appendDayFooter()

        let date = String(format: "%04d-%02d-%02d", script.year, script.month, script.day)
        let header = [
            "dynamic-pomodoro rehearsal — script: \(script.name), seed \(seed)",
            script.summary,
            "\(date) · workday \(TimeFormat.hhmm(script.workdayStartMinutes))–\(TimeFormat.hhmm(script.workdayEndMinutes))"
                + " · focus \(script.minFocusStartMinutes)–\(script.maxFocusMinutes)–\(script.minFocusEndMinutes) min (start–peak–end)"
                + " · library: \(library.count) activities",
        ]
        return Result(script: script, seed: seed, header: header, events: events,
                      findings: findings, entries: store.entries, calendar: calendar)
    }

    /// One second of the world. Order matters and mirrors the real app: the
    /// environment moves first, the user acts, then the timers tick.
    private func stepOneSecond() {
        clock = clock.addingTimeInterval(1)

        // Machine sleep swallows everything: no ticks, no user, no timers.
        if let until = asleepUntil {
            if clock < until { return }
            asleepUntil = nil
            env("the lid opens — the machine wakes")
            // The world may have moved while the machine slept.
            updateCallState()
            // Waking re-ticks immediately (TimerEngine's didWakeNotification
            // observer) and the wake screen is the lock screen.
            screen = .locked
            if let at = unlockAt, at <= clock { unlockAt = clock.addingTimeInterval(5) }
            if unlockAt == nil { unlockAt = clock.addingTimeInterval(5) }
            countdownWakeCheck()
            if tickerRunning { dispatch(.tick(now: clock)) }
            refreshMenuBar()
            return
        }

        updateCallState()
        performScriptedOps()
        performPersonaIntents()

        if tickerRunning { dispatch(.tick(now: clock)) }
        countdownTick()

        // The idle menu-bar title tracks the moving curve (main.swift's
        // idle ticker); recomputing every second and recording only changes
        // is the same behaviour with a finer clock.
        refreshMenuBar()
    }

    // MARK: - Environment

    private func updateCallState() {
        let nowMin = minuteOfDay()
        let live = script.calls.contains { $0.contains(nowMin) }
        if live != onCall {
            onCall = live
            if live {
                env("a call starts — the mic is live")
            } else {
                env("the call ends — the mic goes quiet")
            }
        }
    }

    // MARK: - Scripted user

    private func performScriptedOps() {
        for (index, op) in script.ops.enumerated() where !pendingOpsFired.contains(index) {
            let due: Bool
            switch op.trigger {
            case .at(let minute, let second):
                due = minuteOfDay() == minute && calendar.component(.second, from: clock) == second
            case .breakStarted(let ordinal):
                // "When the nth card appears" — give the user 20s to read it first.
                due = breakOrdinal == ordinal
                    && state.phase.isBreakRunning
                    && secondsIntoBreak() == 20
            case .pendingFor(let seconds):
                due = state.pendingSince.map { clock.timeIntervalSince($0) >= TimeInterval(seconds) } ?? false
            case .countdownStarted(let ordinal):
                due = countdownOrdinal == ordinal && countdownDeadline != nil
            }
            guard due else { continue }
            pendingOpsFired.insert(index)
            perform(op.op)
        }
    }

    private func perform(_ op: RehearsalScript.TimedOp.Op) {
        switch op {
        case .holdSkip:
            guard state.phase.isBreakRunning else { return }
            holdSkipAt = clock
            holdCompletesAt = clock.addingTimeInterval(BreakLogic.skipHoldSeconds)
            let nudge = SkipNudgeMessages.pool.randomElement(using: &rng) ?? ""
            userActed()
            user("you press and hold Skip — the button fills for \(Int(BreakLogic.skipHoldSeconds))s",
                 detail: ["the caption pushes back: “\(nudge)”"])

        case .startBreakNow:
            guard state.phase.isBreakPending else { return }
            userActed()
            user("you pick “Start break now” from the dolphin menu — overriding the call signal")
            breakStartedManuallyAt = clock
            dispatch(.startPendingBreak(now: clock))

        case .abandonFocus:
            guard state.phase.isFocus else { return }
            userActed()
            user("you pick “\(AbandonPrompt.menuTitle)” and confirm “\(AbandonPrompt.confirm)”",
                 detail: ["\(AbandonPrompt.title) — \(AbandonPrompt.message)"])
            dispatch(.abandonFocus(now: clock))

        case .cancelCountdown:
            guard countdownDeadline != nil else { return }
            userActed()
            user("you press Esc — the countdown cancels")
            dismissCountdown(suppress: true)

        case .machineSleep(let untilMinute):
            env("you close the lid — the machine sleeps")
            asleepUntil = date(minute: untilMinute)
            screen = .locked
            sleptDuringBreak = state.phase.isBreakRunning
            // Mirrors AutoStartService.handleLock: a lock during a live
            // countdown dismisses it without suppressing.
            if countdownDeadline != nil {
                dismissCountdown(suppress: false)
                app("[HUD] the countdown vanishes — the screen locked under it")
            }
        }
    }

    // MARK: - Persona (the deterministic habits every script shares)

    private func scheduleNextStart() {
        guard !doneForToday else { return }
        if minuteOfDay() >= script.lastStartMinute {
            doneForToday = true
            nextStartAt = nil
            return
        }
        nextStartAt = clock.addingTimeInterval(TimeInterval(script.startDelaySeconds))
    }

    private func performPersonaIntents() {
        // Start the next session — but never during a call (you are in the
        // meeting), never over a live countdown (it will start on its own).
        if let at = nextStartAt, clock >= at,
           state.phase.isIdle,
           countdownDeadline == nil, !onCall {
            if minuteOfDay() >= script.lastStartMinute {
                doneForToday = true
                nextStartAt = nil
            } else {
                nextStartAt = nil
                userActed()
                user("you click the dolphin — Start focus")
                dispatch(.startFocus(now: clock))
            }
        }

        // Finish an in-flight skip hold.
        if let done = holdCompletesAt {
            if !state.phase.isBreakRunning {
                holdSkipAt = nil; holdCompletesAt = nil
            } else if clock >= done {
                holdSkipAt = nil; holdCompletesAt = nil
                userActed()
                user("the hold completes — break skipped")
                dispatch(.skipBreak(now: clock))
            }
        }

        // Come back to the machine and unlock it.
        if let at = unlockAt, clock >= at, screen != .unlocked, asleepUntil == nil {
            unlockAt = nil
            userActed()
            user("you come back and unlock the screen")
            performUnlock()
        }
    }

    /// Mirrors ScreenLockMonitor.onUnlock → AutoStartService.handleUnlock.
    private func performUnlock() {
        screen = .unlocked
        offerCountdownIfEligible()
    }

    private func userActed() {
        lastUserActionAt = clock
    }

    // MARK: - Dispatch + effect interpretation (mirrors TimerEngine)

    private func dispatch(_ action: PomodoroAction) {
        let effects = PomodoroReducer.reduce(
            &state, action,
            settings: settings, log: store, library: library,
            isOnCall: onCall, rng: &rng, calendar: calendar
        )
        for effect in effects { interpret(effect) }
        handlePhaseChangeIfNeeded()
        refreshMenuBar()
    }

    private func interpret(_ effect: PomodoroEffect) {
        switch effect {
        case .notify(let title, let body, let silent):
            app("[notification] \(title) — \(body)\(silent ? "  (silent)" : "")")
            checkSound(kind: "a notification with sound", silent: silent)

        case .logSession(let entry):
            checkLogEntry(entry)
            store.append(entry)
            app("[log] \(describe(entry))")

        case .playFocusCompleteChime:
            app("♪ Glass — the focus-complete chime")
            checkSound(kind: "the Glass chime", silent: false)

        case .playBreakCompleteChime:
            app("♪ Ping — the break-over chime")
            checkSound(kind: "the Ping chime", silent: false)

        case .startTicker:
            tickerRunning = true

        case .stopTicker:
            tickerRunning = false

        case .lockScreen:
            checkLock()
            screen = .locked
            breakLockedAt = clock
            app("[screen locks] \(Int(PomodoroReducer.breakLockDelaySeconds))s into the break — every display goes to the login window")
            scheduleUnlockAfterLock()

        case .offerAutoStart(let now):
            // Mirrors AutoStartService.offerAfterSkip → offer(now:).
            offerCountdownIfEligible(now: now)

        case .presentMainWindow:
            // Mirrors main.swift presentMainWindow(requireUnlocked: true):
            // never during a call, and only on a positively observed unlock.
            guard !onCall, screen == .unlocked else { return }
            presentMainWindow()

        case .hideMainWindow:
            if mainWindowVisible {
                mainWindowVisible = false
                app("[window] the main window hides — focus is for working")
            }
        }
    }

    /// Mirrors AppDelegate.handlePhaseChange: overlay + phase-scoped menu items.
    private func handlePhaseChangeIfNeeded() {
        let tag = state.phase.tag
        guard tag != lastPhaseTag else { return }
        let previous = lastPhaseTag
        lastPhaseTag = tag

        if previous == breakRunningTag {
            app("[overlay OFF] the screens come back")
            breakStartedManuallyAt = nil
            breakLockedAt = nil
            holdSkipAt = nil
            holdCompletesAt = nil
            sleptDuringBreak = false
        }

        switch state.phase {
        case .idle:
            scheduleNextStart()

        case .focus:
            app("[menu] “\(AbandonPrompt.menuTitle)” appears in the dolphin menu")

        case .breakPending:
            app("[menu] “Start break now” appears in the dolphin menu")
            app("[window] nothing opens — a break owed behind a call stays off the screen")

        case .breakRunning(let deadline, _, let plannedMinutes, let activity, let caption):
            breakOrdinal += 1
            checkBreakStart(activity: activity, plannedMinutes: plannedMinutes)
            var card: [String] = []
            if let line = caption { card.append("“\(line)”") }
            card.append("\(activity.name.uppercased()) — \(activity.instruction)")
            let ringSeconds = max(0, Int(deadline.timeIntervalSince(clock)))
            card.append(String(format: "ring %02d:%02d · Hold to skip", ringSeconds / 60, ringSeconds % 60))
            let manual = breakStartedManuallyAt != nil ? " (started by you)" : ""
            app("[overlay ON] every display blacks out — the \(plannedMinutes)-minute break card\(manual):", detail: card)
        }
    }

    private func presentMainWindow() {
        mainWindowVisible = true
        let suggested = DurationCurve.focusDuration(
            now: clock,
            isFirstSessionOfDay: !store.hasCompletedFocusToday(calendar: calendar, now: clock),
            settings: settings,
            calendar: calendar
        )
        let stats = DailyStats.compute(from: store.entries, calendar: calendar, now: clock)
        app("[window] the main window comes forward — Ready",
            detail: ["Next session: \(suggested) min · [Start focus]",
                     footerText(stats: stats)])
        if state.phase.isFocus {
            finding("\(stamp()) the main window is visible during focus — §4.2 says focus never shows it")
        }
    }

    // MARK: - Auto-start countdown (mirrors AutoStartService)

    private func offerCountdownIfEligible(now: Date? = nil) {
        let now = now ?? clock
        guard countdownDeadline == nil else { return }
        guard !onCall else { return }
        guard let breakEnd = store.lastBreakEnd() else { return }
        guard UnlockGate.shouldOffer(
            phase: state.phase,
            lastBreakEnd: breakEnd,
            suppressedBreakEnd: suppressedBreakEnd,
            now: now,
            windowMinutes: settings.autoStartWindowMinutes
        ) else { return }

        countdownOrdinal += 1
        countdownBreakEnd = breakEnd
        countdownDeadline = now.addingTimeInterval(TimeInterval(settings.autoStartCountdownSeconds))
        app("[HUD] a floating card: “Focus starts in \(settings.autoStartCountdownSeconds)s — Esc or click the menu bar icon to cancel”")
    }

    private func countdownTick() {
        guard let deadline = countdownDeadline else { return }
        let remaining = max(0, Int(ceil(deadline.timeIntervalSince(clock))))
        guard remaining == 0 else { return }
        guard UnlockGate.shouldStillFire(deadline: deadline, now: clock) else {
            dismissCountdown(suppress: false)
            app("[HUD] the countdown lapsed unseen (overslept its deadline) — no session starts")
            return
        }
        countdownDeadline = nil
        countdownBreakEnd = nil
        app("[HUD] the countdown fires")
        dispatch(.startFocus(now: clock))
    }

    /// On wake, an overshot countdown dismisses quietly rather than starting
    /// a session nobody was present to decide on.
    private func countdownWakeCheck() {
        guard let deadline = countdownDeadline, clock > deadline else { return }
        if !UnlockGate.shouldStillFire(deadline: deadline, now: clock) {
            dismissCountdown(suppress: false)
            app("[HUD] the countdown lapsed while the machine slept — no session starts")
        }
    }

    private func dismissCountdown(suppress: Bool) {
        let hadDeadline = countdownDeadline != nil
        if suppress { suppressedBreakEnd = countdownBreakEnd }
        countdownDeadline = nil
        countdownBreakEnd = nil
        guard hadDeadline else { return }
        if suppress {
            // Mirrors AutoStartService.onCancelPresentsWindow →
            // presentMainWindow(requireUnlocked: false): the cancel is proof
            // of presence, so only the call gate applies.
            if !onCall { presentMainWindow() }
        }
    }

    // MARK: - Persona scheduling helpers

    private func scheduleUnlockAfterLock() {
        guard case .breakRunning(let deadline, _, _, _, _) = state.phase else {
            // A lock outside a break would already be a finding; still give
            // the persona a way back in.
            unlockAt = clock.addingTimeInterval(60)
            return
        }
        let offset = script.unlockOffsetsFromBreakEnd.isEmpty
            ? -60
            : script.unlockOffsetsFromBreakEnd[unlockCount % script.unlockOffsetsFromBreakEnd.count]
        unlockCount += 1
        var at = deadline.addingTimeInterval(TimeInterval(offset))
        if at <= clock.addingTimeInterval(2) { at = clock.addingTimeInterval(2) }
        unlockAt = at
    }

    // MARK: - Menu bar (mirrors main.swift updateStatusItemTitle)

    private func refreshMenuBar() {
        let text = MenuBarTitle.text(
            for: state,
            suggestedMinutes: DurationCurve.focusDuration(
                now: clock,
                isFirstSessionOfDay: !store.hasCompletedFocusToday(calendar: calendar, now: clock),
                settings: settings,
                calendar: calendar
            )
        )
        checkMenuBar(text)
        let phaseChanged = state.phase.tag != lastMenuBarPhaseTag
        lastMenuBarPhaseTag = state.phase.tag
        guard text != lastMenuBarText || phaseChanged else { return }
        lastMenuBarText = text
        // Ticking seconds would be one line each; record phase entries and
        // idle-curve movement, not every tick.
        let ticking = state.phase.isFocus
            || state.phase.isBreakRunning
        if !ticking || phaseChanged {
            app("[menu bar] \(text.trimmingCharacters(in: .whitespaces))")
        }
    }

    // MARK: - Invariants

    private func finding(_ text: String) {
        findings.append(text)
    }

    private func stamp() -> String {
        TranscriptRenderer.clock(clock, calendar: calendar)
    }

    /// Principle 7: while a call is live the app makes no sound it wasn't
    /// just asked for. "Just asked" means a user action this same second —
    /// the click that starts a session or forces the owed break.
    private func checkSound(kind: String, silent: Bool) {
        guard onCall, !silent else { return }
        if lastUserActionAt == clock { return }
        finding("\(stamp()) \(kind) sounded during a live call, unasked — principle 7")
    }

    private func checkLock() {
        guard case .breakRunning(_, let startedAt, _, _, _) = state.phase else {
            finding("\(stamp()) the screen locked outside a running break")
            return
        }
        if breakLockedAt != nil {
            finding("\(stamp()) the screen locked twice in one break")
        }
        let elapsed = clock.timeIntervalSince(startedAt)
        // A lid-close inside the pre-lock window legitimately delays the
        // lock until the wake tick, so exact timing only holds sleep-free.
        if !sleptDuringBreak, abs(elapsed - PomodoroReducer.breakLockDelaySeconds) > 1.5 {
            finding("\(stamp()) the break lock fired \(Int(elapsed))s in — expected \(Int(PomodoroReducer.breakLockDelaySeconds))s")
        }
        if onCall && breakStartedManuallyAt == nil {
            finding("\(stamp()) the app locked the screen during a call it wasn't overriding — principle 7")
        }
    }

    private func checkBreakStart(activity: Activity, plannedMinutes: Int) {
        if onCall && breakStartedManuallyAt == nil {
            finding("\(stamp()) the break overlay appeared during a call the user didn't override — principle 7")
        }

        // The pick must come from the selector's own candidate pool,
        // recomputed against the same log state the reducer saw.
        if !library.isEmpty {
            let pool = ActivitySelector.candidatePool(
                from: library,
                breakMinutes: plannedMinutes,
                now: clock,
                recentActivityIDs: store.recentBreakActivityIDs(),
                lastCategory: store.lastBreakCategory(library: library),
                settings: settings,
                calendar: calendar
            )
            if !pool.contains(activity) {
                finding("\(stamp()) break card shows “\(activity.name)” which the selection rules exclude right now")
            }
        }
    }

    private func checkLogEntry(_ entry: SessionLogEntry) {
        if let last = store.entries.last, entry.endedAt < last.endedAt {
            finding("\(stamp()) log entry \(entry.kind.rawValue) ends before the previous entry — the log ran backwards")
        }
        if entry.startedAt > entry.endedAt {
            finding("\(stamp()) log entry \(entry.kind.rawValue) ends before it starts")
        }
        if entry.kind == .breakCompleted || entry.kind == .breakSkipped,
           entry.activityID != nil,
           let focus = store.entries.last(where: { $0.kind == .focusCompleted }) {
            let expected = BreakLogic.breakDuration(forFocusMinutes: focus.plannedMinutes)
            if entry.plannedMinutes != expected {
                finding("\(stamp()) a \(focus.plannedMinutes)-min focus earned a \(entry.plannedMinutes)-min break — the rule says \(expected)")
            }
        }
    }

    private func checkMenuBar(_ text: String) {
        let ok: Bool
        switch state.phase {
        case .idle: ok = text.hasPrefix(" Start ") && text.hasSuffix("m")
        case .focus: ok = text.hasPrefix(" F ") && text.count == 8
        case .breakPending: ok = text == " B …"
        case .breakRunning: ok = text.hasPrefix(" B ") && text.count == 8
        }
        if !ok {
            finding("\(stamp()) menu-bar title “\(text)” doesn't match the phase")
        }
    }

    // MARK: - Rendering helpers

    private func describe(_ entry: SessionLogEntry) -> String {
        let from = TranscriptRenderer.clock(entry.startedAt, calendar: calendar)
        let to = TranscriptRenderer.clock(entry.endedAt, calendar: calendar)
        let activity = entry.activityID.map { " · \($0)" } ?? ""
        return "\(entry.kind.rawValue) \(from)–\(to) · \(entry.plannedMinutes) min\(activity)"
    }

    private func footerText(stats: DailyStats) -> String {
        "footer: \(TimeFormat.duration(stats.totalSeconds)) today · \(TimeFormat.pomos(stats.pomoCount)) · \(TimeFormat.duration(stats.focusSeconds)) focus"
    }

    private func appendDayFooter() {
        let stats = DailyStats.compute(from: store.entries, calendar: calendar, now: clock)
        let focus = store.entries.filter { $0.kind == .focusCompleted }.count
        let abandoned = store.entries.filter { $0.kind == .focusAbandoned }.count
        let breaks = store.entries.filter { $0.kind == .breakCompleted }.count
        let skipped = store.entries.filter { $0.kind == .breakSkipped }.count
        app("[day] \(footerText(stats: stats))")
        app("[day] \(focus) focus completed · \(abandoned) abandoned · \(breaks) breaks taken · \(skipped) skipped")
    }

    private func minuteOfDay() -> Int {
        TimeFormat.minutesSinceMidnight(from: clock, calendar: calendar)
    }

    private func secondsIntoBreak() -> Int {
        guard case .breakRunning(_, let startedAt, _, _, _) = state.phase else { return -1 }
        return Int(clock.timeIntervalSince(startedAt))
    }

    private func date(minute: Int) -> Date {
        var comps = DateComponents()
        comps.year = script.year; comps.month = script.month; comps.day = script.day
        comps.hour = minute / 60; comps.minute = minute % 60
        return calendar.date(from: comps)!
    }

    private func user(_ text: String, detail: [String] = []) {
        events.append(TranscriptEvent(at: clock, kind: .user, text: text, detail: detail))
    }

    private func app(_ text: String, detail: [String] = []) {
        events.append(TranscriptEvent(at: clock, kind: .app, text: text, detail: detail))
    }

    private func env(_ text: String) {
        events.append(TranscriptEvent(at: clock, kind: .env, text: text))
    }
}

/// Rehearsal-local phase predicates — comparing a phase to "any breakRunning"
/// needs a spelled-out `if case` per site otherwise.
private extension PomodoroState.Phase {
    var isIdle: Bool { if case .idle = self { return true }; return false }
    var isFocus: Bool { if case .focus = self { return true }; return false }
    var isBreakPending: Bool { if case .breakPending = self { return true }; return false }
    var isBreakRunning: Bool { if case .breakRunning = self { return true }; return false }
}
