import Foundation
import SwiftUI

/// User-configurable settings, persisted in UserDefaults.
/// Kept intentionally small — v1 exposes only what the spec calls out in §7.
final class Settings: ObservableObject {
    static let shared = Settings()

    // Keys
    private enum Key {
        static let workdayStartMinutes = "workdayStartMinutes"
        static let workdayEndMinutes = "workdayEndMinutes"
        static let minFocusMinutes = "minFocusMinutes"
        static let maxFocusMinutes = "maxFocusMinutes"
        static let soundEnabled = "soundEnabled"
        static let disabledCategories = "disabledCategories"
        static let onboardingComplete = "onboardingComplete"
        static let calendarSyncEnabled = "calendarSyncEnabled"
        static let calendarIdentifier = "calendarIdentifier"
    }

    // Stored state (minutes since midnight for times)
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
    @Published var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: Key.soundEnabled) }
    }
    @Published var disabledCategories: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(disabledCategories), forKey: Key.disabledCategories)
        }
    }
    @Published var onboardingComplete: Bool {
        didSet { UserDefaults.standard.set(onboardingComplete, forKey: Key.onboardingComplete) }
    }
    /// Mirror break sessions to Calendar so they sync to iPhone / Watch via iCloud.
    @Published var calendarSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(calendarSyncEnabled, forKey: Key.calendarSyncEnabled) }
    }
    /// EKCalendar identifier to write break events to. Nil → system default.
    @Published var calendarIdentifier: String? {
        didSet { UserDefaults.standard.set(calendarIdentifier, forKey: Key.calendarIdentifier) }
    }

    private init() {
        let d = UserDefaults.standard
        self.workdayStartMinutes = d.object(forKey: Key.workdayStartMinutes) as? Int ?? (9 * 60)
        self.workdayEndMinutes = d.object(forKey: Key.workdayEndMinutes) as? Int ?? (18 * 60)
        self.minFocusMinutes = d.object(forKey: Key.minFocusMinutes) as? Int ?? 20
        self.maxFocusMinutes = d.object(forKey: Key.maxFocusMinutes) as? Int ?? 40
        self.soundEnabled = d.object(forKey: Key.soundEnabled) as? Bool ?? true
        self.disabledCategories = Set((d.array(forKey: Key.disabledCategories) as? [String]) ?? [])
        self.onboardingComplete = d.bool(forKey: Key.onboardingComplete)
        self.calendarSyncEnabled = d.bool(forKey: Key.calendarSyncEnabled)
        self.calendarIdentifier = d.string(forKey: Key.calendarIdentifier)
    }

    /// Workday midpoint in minutes since midnight.
    var midpointMinutes: Int {
        (workdayStartMinutes + workdayEndMinutes) / 2
    }

    /// Half-length of the workday in minutes.
    var halfDayMinutes: Int {
        (workdayEndMinutes - workdayStartMinutes) / 2
    }
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
