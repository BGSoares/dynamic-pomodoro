import Foundation
// ObservableObject/@Published come from Combine (shimmed on Linux, where
// nothing observes — see CombineShim.swift). SwiftUI itself is never needed
// in the models layer.
#if canImport(Combine)
import Combine
#endif

/// User-configurable settings, persisted in UserDefaults.
/// Four values shown in `SettingsView` — that's the whole personalisation
/// surface (PURPOSE principle 5). Two more live here unexposed: opinionated
/// timings for the unlock auto-start countdown, tunable via `defaults write`
/// but deliberately absent from the UI, same posture as the reducer's
/// hardcoded timing constants.
final class Settings: ObservableObject {
    static let shared = Settings()

    private enum Key {
        static let workdayStartMinutes = "workdayStartMinutes"
        static let workdayEndMinutes = "workdayEndMinutes"
        static let minFocusMinutes = "minFocusMinutes"
        static let maxFocusMinutes = "maxFocusMinutes"
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
    @Published var minFocusMinutes: Int {
        didSet { defaults.set(minFocusMinutes, forKey: Key.minFocusMinutes) }
    }
    @Published var maxFocusMinutes: Int {
        didSet { defaults.set(maxFocusMinutes, forKey: Key.maxFocusMinutes) }
    }
    /// HUD countdown length before an owed-nothing unlock auto-starts focus.
    @Published var autoStartCountdownSeconds: Int {
        didSet { defaults.set(autoStartCountdownSeconds, forKey: Key.autoStartCountdownSeconds) }
    }
    /// How long after a break ends an unlock still counts as "just back" (§3, G3).
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
        let minF = defaults.object(forKey: Key.minFocusMinutes) as? Int ?? 20
        let maxF = defaults.object(forKey: Key.maxFocusMinutes) as? Int ?? 40
        let countdown = defaults.object(forKey: Key.autoStartCountdownSeconds) as? Int ?? 15
        let window = defaults.object(forKey: Key.autoStartWindowMinutes) as? Int ?? 20

        let clampedStart = min(max(start, 0), 23 * 60 + 45)
        let clampedEnd = min(max(end, clampedStart + 60), 24 * 60)
        let clampedMax = min(max(max(maxF, 10), min(max(minF, 5), 60) + 5), 90)

        workdayStartMinutes = min(clampedStart, clampedEnd - 60)
        workdayEndMinutes = clampedEnd
        minFocusMinutes = min(min(max(minF, 5), 60), clampedMax - 5)
        maxFocusMinutes = clampedMax
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
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
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
