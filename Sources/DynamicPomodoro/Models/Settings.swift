import Foundation
import SwiftUI

/// User-configurable settings, persisted in UserDefaults.
/// Four values. That's the whole surface.
final class Settings: ObservableObject {
    static let shared = Settings()

    private enum Key {
        static let workdayStartMinutes = "workdayStartMinutes"
        static let workdayEndMinutes = "workdayEndMinutes"
        static let minFocusMinutes = "minFocusMinutes"
        static let maxFocusMinutes = "maxFocusMinutes"
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

        let clampedStart = min(max(start, 0), 23 * 60 + 45)
        let clampedEnd = min(max(end, clampedStart + 60), 24 * 60)
        let clampedMax = min(max(max(maxF, 10), min(max(minF, 5), 60) + 5), 90)

        workdayStartMinutes = min(clampedStart, clampedEnd - 60)
        workdayEndMinutes = clampedEnd
        minFocusMinutes = min(min(max(minF, 5), 60), clampedMax - 5)
        maxFocusMinutes = clampedMax
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

    static func minutesSinceMidnight(from date: Date, calendar: Calendar = .current) -> Int {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }
}
