import Foundation

/// Shared Application Support directory and codecs for all on-disk persistence.
enum AppSupport {
    static var directory: URL {
        #if DEBUG
        // Test seam: lets E2E runs point persistence at a scratch directory
        // instead of the real Application Support folder.
        if let override = ProcessInfo.processInfo.environment["DP_APP_SUPPORT_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        // A compressed-time run (DP_SECONDS_PER_MINUTE) plays fabricated
        // sessions; they must never land in the real log, so persistence
        // auto-redirects to a scratch directory unless one was chosen above.
        if TimeScale.isCompressed {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("DynamicPomodoro-compressed", isDirectory: true)
        }
        #endif
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        return base.appendingPathComponent("DynamicPomodoro", isDirectory: true)
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

/// One entry per focus session or break, for the success-metrics review (§10).
/// Stored as a single pretty-printed JSON array in Application Support.
struct SessionLogEntry: Codable, Equatable {
    enum Kind: String, Codable {
        case focusCompleted
        case focusAbandoned
        case breakCompleted
        case breakSkipped
    }

    let kind: Kind
    let startedAt: Date
    let endedAt: Date
    let plannedMinutes: Int
    let activityID: String?   // break kinds only
}

/// Aggregate of focus + break time for a given day.
/// Completed focus contributes 1.0 to pomoCount and its planned duration to time.
/// Abandoned focus contributes a fractional pomo (elapsed / planned, capped at 1.0)
/// and its elapsed seconds. Skipped breaks are excluded — the break didn't happen.
struct DailyStats: Equatable {
    let pomoCount: Double
    let focusSeconds: Int
    let breakSeconds: Int

    var totalSeconds: Int { focusSeconds + breakSeconds }

    static let empty = DailyStats(pomoCount: 0, focusSeconds: 0, breakSeconds: 0)

    static func + (lhs: DailyStats, rhs: DailyStats) -> DailyStats {
        DailyStats(
            pomoCount: lhs.pomoCount + rhs.pomoCount,
            focusSeconds: lhs.focusSeconds + rhs.focusSeconds,
            breakSeconds: lhs.breakSeconds + rhs.breakSeconds
        )
    }

    /// What one entry contributes to the totals of the day it started on.
    /// Split out from `compute` so the idle footer's "today" and the stats
    /// window's per-day bars can never disagree about what a session was
    /// worth — there is one rule, in one place.
    static func contribution(of e: SessionLogEntry) -> DailyStats {
        switch e.kind {
        case .focusCompleted:
            return DailyStats(pomoCount: 1, focusSeconds: e.plannedMinutes * 60, breakSeconds: 0)
        case .focusAbandoned:
            let planned = Double(e.plannedMinutes * 60)
            // Clamped to the planned span. An abandon happens *during* the
            // session and the slept-through path logs exactly the deadline,
            // so elapsed can only exceed planned if the file was hand-edited
            // or the clock jumped. Clamping keeps focusSeconds agreeing with
            // pomoCount (always capped at one pomo) and keeps the `Int(...)`
            // below total, which matters now that FocusHistory folds the
            // whole log rather than just today's entries.
            let elapsed = min(max(0, e.endedAt.timeIntervalSince(e.startedAt)), planned)
            return DailyStats(
                pomoCount: planned > 0 ? elapsed / planned : 0,
                focusSeconds: Int(elapsed),
                breakSeconds: 0
            )
        case .breakCompleted:
            return DailyStats(pomoCount: 0, focusSeconds: 0, breakSeconds: e.plannedMinutes * 60)
        case .breakSkipped:
            return .empty
        }
    }

    static func compute(
        from entries: [SessionLogEntry],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> DailyStats {
        entries
            .filter { calendar.isDate($0.startedAt, inSameDayAs: now) }
            .reduce(DailyStats.empty) { $0 + DailyStats.contribution(of: $1) }
    }
}

extension SessionLogEntry {
    /// Shorter call-site form used by the reducer.
    init(kind: Kind, from startedAt: Date, to endedAt: Date, minutes: Int, activity activityID: String? = nil) {
        self.kind = kind
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.plannedMinutes = minutes
        self.activityID = activityID
    }
}

/// Generic append-only JSON array persisted to a single file in Application Support.
/// Shared by SessionLogStore and FeedbackStore to avoid duplicating load/save boilerplate.
/// Main-thread only: every caller (TimerEngine, views) is @MainActor, so no
/// internal synchronization is needed.
final class JSONArrayStore<Element: Codable> {
    private(set) var elements: [Element] = []
    private let fileURL: URL

    init(directory: URL, filename: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent(filename)
        load()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? AppSupport.decoder.decode([Element].self, from: data) else {
            // Unreadable or corrupt: preserve the file — the rename signals
            // the problem without destroying history, and the next save()
            // would otherwise clobber it.
            let backup = fileURL.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            return
        }
        elements = decoded
    }

    private func save() {
        guard let data = try? AppSupport.encoder.encode(elements) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func append(_ element: Element) {
        elements.append(element)
        save()
    }
}

/// Persists session log + recent-activity recency window.
/// Reads are synchronous; the data volume is small (one user, one machine).
final class SessionLogStore {
    static let shared = SessionLogStore()
    private let store: JSONArrayStore<SessionLogEntry>
    var entries: [SessionLogEntry] { store.elements }

    private convenience init() { self.init(directory: AppSupport.directory) }

    /// Construct against an explicit directory. Used by tests to point at a
    /// temp dir instead of the user's real Application Support folder.
    init(directory: URL) {
        store = JSONArrayStore(directory: directory, filename: "sessions.json")
    }

    func append(_ entry: SessionLogEntry) { store.append(entry) }

    /// Has a focus session been *completed* today (user-local day)?
    /// Decides whether the next session is the day's first, which forces the
    /// curve to its minimum duration. Only completed focus counts: a
    /// one-minute abandoned attempt provides no warm-up, so it must not
    /// consume the day's short first session.
    func hasCompletedFocusToday(calendar: Calendar = .current, now: Date = Date()) -> Bool {
        entries.contains { $0.kind == .focusCompleted && calendar.isDate($0.startedAt, inSameDayAs: now) }
    }

    /// Most recent break-activity IDs, newest first.
    func recentBreakActivityIDs(limit: Int = 5) -> [String] {
        Array(entries.reversed().compactMap(\.activityID).prefix(limit))
    }

    /// Start times of today's breaks that actually put a card on screen,
    /// chronological — the input to nudge assignment (`Nudges.assign`).
    ///
    /// A break capped out by a long call is logged as skipped with no activity
    /// because nothing was ever displayed, so `activityID` is the discriminator
    /// for "the user saw this break" — the same signal `recentBreakActivityIDs`
    /// leans on. Without that filter an unseen break would silently spend the
    /// day's nudge.
    func shownBreakStartsToday(calendar: Calendar = .current, now: Date = Date()) -> [Date] {
        entries.filter {
            $0.activityID != nil
                && ($0.kind == .breakCompleted || $0.kind == .breakSkipped)
                && calendar.isDate($0.startedAt, inSameDayAs: now)
        }.map(\.startedAt)
    }

    /// Category of the most recent break activity, if any.
    func lastBreakCategory(library: [Activity]) -> Activity.Category? {
        guard let lastID = entries.last(where: { $0.activityID != nil })?.activityID else { return nil }
        return library.first(where: { $0.id == lastID })?.category
    }

    /// Aggregate completed focus + break time for the given day.
    func dailyStats(calendar: Calendar = .current, now: Date = Date()) -> DailyStats {
        DailyStats.compute(from: entries, calendar: calendar, now: now)
    }

    /// The trailing calendar weeks the stats window draws, oldest first.
    func focusWeeks(
        weekCount: Int = FocusHistory.defaultWeekCount,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [FocusWeek] {
        FocusHistory.weeks(from: entries, weekCount: weekCount, calendar: calendar, now: now)
    }

    /// The moment the most recent break ended (completed or skipped) — but
    /// only if nothing has run since. Entries are appended in chronological
    /// order and logged at the *end* of a phase, so "the log's last entry is
    /// a break end" already means "no focus has started after it"; the
    /// caller pairs this with the engine's own idle check (a focus in
    /// progress hasn't logged anything yet, so it wouldn't show up here
    /// either way, but the phase check is the authoritative "nothing is
    /// running" signal).
    func lastBreakEnd() -> Date? {
        guard let last = entries.last,
              last.kind == .breakCompleted || last.kind == .breakSkipped
        else { return nil }
        return last.endedAt
    }
}
