import Foundation

/// One entry per focus session or break, for the success-metrics review (§10).
/// Stored as JSON lines in Application Support.
struct SessionLogEntry: Codable {
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

    static func compute(
        from entries: [SessionLogEntry],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> DailyStats {
        var pomoCount = 0.0
        var focusSeconds = 0
        var breakSeconds = 0
        for e in entries where calendar.isDate(e.startedAt, inSameDayAs: now) {
            switch e.kind {
            case .focusCompleted:
                pomoCount += 1.0
                focusSeconds += e.plannedMinutes * 60
            case .focusAbandoned:
                let elapsed = max(0, e.endedAt.timeIntervalSince(e.startedAt))
                let plannedSeconds = Double(e.plannedMinutes * 60)
                let proportion = plannedSeconds > 0 ? min(elapsed / plannedSeconds, 1.0) : 0
                pomoCount += proportion
                focusSeconds += Int(elapsed)
            case .breakCompleted:
                breakSeconds += e.plannedMinutes * 60
            case .breakSkipped:
                break
            }
        }
        return DailyStats(pomoCount: pomoCount, focusSeconds: focusSeconds, breakSeconds: breakSeconds)
    }
}

/// Persists session log + recent-activity recency window.
/// Reads are synchronous; the data volume is small (one user, one machine).
final class SessionLogStore {
    static let shared = SessionLogStore()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "pomodoro.sessionlog")
    private(set) var entries: [SessionLogEntry] = []

    private init() {
        let fm = FileManager.default
        let dir: URL
        if let supportDir = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            dir = supportDir.appendingPathComponent("DynamicPomodoro", isDirectory: true)
        } else {
            dir = fm.temporaryDirectory.appendingPathComponent("DynamicPomodoro", isDirectory: true)
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("sessions.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.entries = (try? dec.decode([SessionLogEntry].self, from: data)) ?? []
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func append(_ entry: SessionLogEntry) {
        queue.sync {
            entries.append(entry)
            save()
        }
    }

    /// Has any focus or break entry been recorded today (user-local day)?
    func hasEntryToday(calendar: Calendar = .current, now: Date = Date()) -> Bool {
        entries.contains { calendar.isDate($0.startedAt, inSameDayAs: now) }
    }

    /// Has the user completed (or skipped) any *break* today?
    /// Used to decide whether to show the first-of-day reminder message.
    func hasBreakEntryToday(calendar: Calendar = .current, now: Date = Date()) -> Bool {
        entries.contains { e in
            (e.kind == .breakCompleted || e.kind == .breakSkipped) &&
            calendar.isDate(e.startedAt, inSameDayAs: now)
        }
    }

    /// Most recent break-activity IDs, newest first.
    func recentBreakActivityIDs(limit: Int = 5) -> [String] {
        entries.reversed()
            .compactMap { $0.activityID }
            .prefix(limit)
            .map { $0 }
    }

    /// Category of the most recent break activity, if any.
    func lastBreakCategory(library: [Activity]) -> Activity.Category? {
        guard let lastID = entries.reversed().compactMap({ $0.activityID }).first else { return nil }
        return library.first(where: { $0.id == lastID })?.category
    }

    /// Was the most recent break (completed or skipped) a skip?
    func lastBreakWasSkipped() -> Bool {
        for e in entries.reversed() {
            if e.kind == .breakCompleted { return false }
            if e.kind == .breakSkipped { return true }
        }
        return false
    }

    /// Aggregate completed focus + break time for the given day.
    func dailyStats(calendar: Calendar = .current, now: Date = Date()) -> DailyStats {
        DailyStats.compute(from: entries, calendar: calendar, now: now)
    }
}
