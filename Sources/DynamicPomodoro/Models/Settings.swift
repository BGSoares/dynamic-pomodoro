import Foundation
// ObservableObject/@Published come from Combine (shimmed on Linux, where
// nothing observes — see CombineShim.swift). SwiftUI itself is never needed
// in the models layer.
#if canImport(Combine)
import Combine
#endif

/// User-configurable settings, persisted in UserDefaults.
/// Six values shown in `SettingsView` – that's the whole personalisation
/// surface (PURPOSE principle 5). Two more live here unexposed: opinionated
/// timings for the unlock auto-start countdown, tunable via `defaults write`
/// but deliberately absent from the UI, same posture as the reducer's
/// hardcoded timing constants.
final class Settings: ObservableObject {
    static let shared = Settings()

    private enum Key {
        static let workdayStartMinutes = "workdayStartMinutes"
        static let workdayEndMinutes = "workdayEndMinutes"
        static let minFocusStartMinutes = "minFocusStartMinutes"
        static let minFocusEndMinutes = "minFocusEndMinutes"
        /// The one minimum both ends of the day shared until 2026-10-05.
        /// Read only as the default for the two keys that replaced it, so
        /// an upgrade leaves the curve exactly where it was; never written.
        static let legacyMinFocusMinutes = "minFocusMinutes"
        static let maxFocusMinutes = "maxFocusMinutes"
        static let pauseMediaOnBreak = "pauseMediaOnBreak"
        static let autoStartCountdownSeconds = "autoStartCountdownSeconds"
        static let autoStartWindowMinutes = "autoStartWindowMinutes"
    }

    private let defaults: UserDefaults

    @Published var workdayStartMinutes: Int {
        didSet { defaults.set(workdayStartMinutes, forKey: Key.workdayStartMinutes) }
    }
    @Published var workdayEndMinutes: Int {
        didSet { defaults.set(workdayEndMinutes, forKey: Key.workdayEndMinutes) }
    }
    /// The curve's floor at the start of the workday – and the length of
    /// the day's first session, which is the warm-up whatever the clock says.
    @Published var minFocusStartMinutes: Int {
        didSet { defaults.set(minFocusStartMinutes, forKey: Key.minFocusStartMinutes) }
    }
    /// The curve's floor at the end of the workday. Its own number so the
    /// afternoon can taper gently while the morning still warms up from
    /// short; one shared minimum forced the two ends to match.
    @Published var minFocusEndMinutes: Int {
        didSet { defaults.set(minFocusEndMinutes, forKey: Key.minFocusEndMinutes) }
    }
    @Published var maxFocusMinutes: Int {
        didSet { defaults.set(maxFocusMinutes, forKey: Key.maxFocusMinutes) }
    }
    /// Pause whatever is playing (Spotify, a YouTube tab…) as a break starts.
    /// Off until ticked: an update shouldn't start reaching into other apps
    /// on its own.
    @Published var pauseMediaOnBreak: Bool {
        didSet { defaults.set(pauseMediaOnBreak, forKey: Key.pauseMediaOnBreak) }
    }
    /// HUD countdown length before an owed-nothing unlock auto-starts focus.
    @Published var autoStartCountdownSeconds: Int {
        didSet { defaults.set(autoStartCountdownSeconds, forKey: Key.autoStartCountdownSeconds) }
    }
    /// How long after the loop last turned (the latest log entry's end) an
    /// unlock still counts as a return to it (§3, G3).
    @Published var autoStartWindowMinutes: Int {
        didSet { defaults.set(autoStartWindowMinutes, forKey: Key.autoStartWindowMinutes) }
    }

    /// `defaults` is injectable so tests run against a scratch suite instead
    /// of mutating the real domain through the shared singleton.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Clamp persisted values to the same bounds SettingsView enforces.
        // UserDefaults contents are not trusted input (manual `defaults
        // write`, domain migration) and the curve math assumes sane ranges.
        let start = defaults.object(forKey: Key.workdayStartMinutes) as? Int ?? (9 * 60)
        let end = defaults.object(forKey: Key.workdayEndMinutes) as? Int ?? (18 * 60)
        let legacyMin = defaults.object(forKey: Key.legacyMinFocusMinutes) as? Int
        let minStart = defaults.object(forKey: Key.minFocusStartMinutes) as? Int ?? legacyMin ?? 20
        let minEnd = defaults.object(forKey: Key.minFocusEndMinutes) as? Int ?? legacyMin ?? 20
        let maxF = defaults.object(forKey: Key.maxFocusMinutes) as? Int ?? 40
        let countdown = defaults.object(forKey: Key.autoStartCountdownSeconds) as? Int ?? 15
        let window = defaults.object(forKey: Key.autoStartWindowMinutes) as? Int ?? 120

        let clampedStart = min(max(start, 0), 23 * 60 + 45)
        let clampedEnd = min(max(end, clampedStart + 60), 24 * 60)
        let clampedMinStart = min(max(minStart, 5), 60)
        let clampedMinEnd = min(max(minEnd, 5), 60)
        // The maximum stays above both floors, as the view's steppers keep it.
        let clampedMax = min(max(max(maxF, 10), max(clampedMinStart, clampedMinEnd) + 5), 90)

        workdayStartMinutes = min(clampedStart, clampedEnd - 60)
        workdayEndMinutes = clampedEnd
        minFocusStartMinutes = min(clampedMinStart, clampedMax - 5)
        minFocusEndMinutes = min(clampedMinEnd, clampedMax - 5)
        maxFocusMinutes = clampedMax
        pauseMediaOnBreak = defaults.object(forKey: Key.pauseMediaOnBreak) as? Bool ?? false
        autoStartCountdownSeconds = min(max(countdown, 3), 120)
        autoStartWindowMinutes = min(max(window, 1), 180)
    }

    var midpointMinutes: Int { (workdayStartMinutes + workdayEndMinutes) / 2 }
    var halfDayMinutes: Int { (workdayEndMinutes - workdayStartMinutes) / 2 }
}

enum TimeFormat {
    static func hhmm(_ minutesSinceMidnight: Int) -> String {
        let h = minutesSinceMidnight / 60
        let m = minutesSinceMidnight % 60
        return String(format: "%02d:%02d", h, m)
    }

    /// Compact hours + minutes: "0m", "45m", "2h", "2h 15m". Shared by the
    /// idle footer and the stats window so the two never phrase the same
    /// number differently.
    static func duration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60
        return h == 0 ? "\(m)m" : m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    static func minutesSinceMidnight(from date: Date, calendar: Calendar = .current) -> Int {
        secondsSinceMidnight(from: date, calendar: calendar) / 60
    }

    /// Wall-clock seconds since midnight – by components, not by elapsed
    /// time since midnight, so a DST day still reads at the hour the clock
    /// on the wall showed.
    static func secondsSinceMidnight(from date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return (c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0)
    }

    /// "0 pomos", "1 pomo", "3.5 pomos" — one decimal at most, dropped when
    /// whole. Shared by the idle footer and the rehearsal transcript so the
    /// rehearsed day reads exactly what the window would say.
    static func pomos(_ count: Double) -> String {
        let v = (count * 10).rounded() / 10
        let n = v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%.1f", v)
        return "\(n) pomo\(v == 1 ? "" : "s")"
    }
}
