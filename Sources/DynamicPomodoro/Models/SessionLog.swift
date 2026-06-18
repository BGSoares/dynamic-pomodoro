import Foundation

/// Shared Application Support directory and codecs for all on-disk persistence.
enum AppSupport {
    static var directory: URL {
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
/// Stored as JSON lines in Application Support.
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
                pomoCount += 1
                focusSeconds += e.plannedMinutes * 60
            case .focusAbandoned:
                let elapsed = max(0, e.endedAt.timeIntervalSince(e.startedAt))
                let planned = Double(e.plannedMinutes * 60)
                pomoCount += planned > 0 ? min(elapsed / planned, 1.0) : 0
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
/// Shared by SessionLogStore and FeedbackStore to avoid duplicating load/save/queue boilerplate.
final class JSONArrayStore<Element: Codable> {
    private(set) var elements: [Element] = []
    private let fileURL: URL
    private let queue: DispatchQueue

    init(directory: URL, filename: String, label: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent(filename)
        queue = DispatchQueue(label: label)
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? AppSupport.decoder.decode([Element].self, from: data) else {
            // Preserve corrupted file — the rename signals corruption without destroying history.
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
        queue.sync { elements.append(element); save() }
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
        store = JSONArrayStore(directory: directory, filename: "sessions.json", label: "pomodoro.sessionlog")
    }

    func append(_ entry: SessionLogEntry) { store.append(entry) }

    /// Has any focus or break entry been recorded today (user-local day)?
    /// Used to decide whether the next focus session is the day's first
    /// (which forces the curve to its minimum duration).
    func hasEntryToday(calendar: Calendar = .current, now: Date = Date()) -> Bool {
        entries.contains { calendar.isDate($0.startedAt, inSameDayAs: now) }
    }

    /// Most recent break-activity IDs, newest first.
    func recentBreakActivityIDs(limit: Int = 5) -> [String] {
        Array(entries.reversed().compactMap(\.activityID).prefix(limit))
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

    /// Total completed focus sessions across all time — gates the
    /// once-per-user feedback prompt.
    func completedFocusCount() -> Int {
        entries.lazy.filter { $0.kind == .focusCompleted }.count
    }
}
