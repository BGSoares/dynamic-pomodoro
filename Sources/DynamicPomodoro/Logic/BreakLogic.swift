import Foundation

/// Break = max(20% of focus session, 5 minutes) — §4.1.
enum BreakLogic {
    static let floorMinutes: Int = 5

    static func breakDuration(forFocusMinutes focus: Int) -> Int {
        max(Int((Double(focus) * 0.2).rounded()), floorMinutes)
    }

    /// Returns "short" or "medium" to match the activity library's duration bands.
    static func durationBand(forBreakMinutes m: Int) -> Activity.DurationBand {
        // short: 5–6 min, medium: 7–8 min (and up)
        m <= 6 ? .short : .medium
    }
}
