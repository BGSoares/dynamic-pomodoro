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

    @Published var workdayStartMinutes: Int {
        didSet { UserDefaults.standard.set(workdayStartMinutes, forKey: Key.workdayStartMinutes) }
    }
    @Published var workdayEndMinutes: Int {
        didSet { UserDefaults.standard.set(workdayEndMinutes, forKey: Key.workdayEndMinutes) }
    }
    @Published var minFocusMinutes: Int {
        didSet { UserDefaults.standard.set(minFocusMinutes, forKey: Key.minFocusMinutes) }
    }
    @Published var maxFocusMinutes: Int {
        didSet { UserDefaults.standard.set(maxFocusMinutes, forKey: Key.maxFocusMinutes) }
    }

    private init() {
        let d = UserDefaults.standard
        self.workdayStartMinutes = d.object(forKey: Key.workdayStartMinutes) as? Int ?? (9 * 60)
        self.workdayEndMinutes = d.object(forKey: Key.workdayEndMinutes) as? Int ?? (18 * 60)
        self.minFocusMinutes = d.object(forKey: Key.minFocusMinutes) as? Int ?? 20
        self.maxFocusMinutes = d.object(forKey: Key.maxFocusMinutes) as? Int ?? 40
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
