import Foundation

struct Activity: Identifiable, Codable, Hashable {
    enum Category: String, Codable, CaseIterable {
        case stretch, breathwork
        case eyeRest = "eye_rest"
        case walk, mindfulness, hydration

        var displayName: String {
            switch self {
            case .stretch: return "Stretch"
            case .breathwork: return "Breathwork"
            case .eyeRest: return "Eye rest"
            case .walk: return "Walk"
            case .mindfulness: return "Mindfulness"
            case .hydration: return "Hydration"
            }
        }
    }

    enum DurationBand: String, Codable, CaseIterable {
        case short, medium

        var displayName: String {
            switch self {
            case .short: return "Short (≤6 min)"
            case .medium: return "Medium (7+ min)"
            }
        }
    }

    enum Energy: String, Codable, CaseIterable {
        case gentle, moderate, active

        var displayName: String {
            switch self {
            case .gentle: return "Gentle"
            case .moderate: return "Moderate"
            case .active: return "Active"
            }
        }
    }

    enum TimeOfDay: String, Codable, CaseIterable {
        case morning, midday, afternoon
        case endOfDay = "end_of_day"

        var displayName: String {
            switch self {
            case .morning: return "Morning"
            case .midday: return "Midday"
            case .afternoon: return "Afternoon"
            case .endOfDay: return "End of day"
            }
        }
    }

    let id: String
    let name: String
    let instruction: String
    let category: Category
    let band: DurationBand
    let energy: Energy
    let suitableTimes: [TimeOfDay]

    enum CodingKeys: String, CodingKey {
        case id, name, instruction, category, band, energy
        case suitableTimes = "suitable_times"
    }
}

enum ActivityLibrary {
    /// Load the bundled activities.json.
    /// Checks Bundle.module first (SPM / `swift run`), then Bundle.main
    /// (`.app` bundle where the build script copies the file to Contents/Resources).
    static func load() -> [Activity] {
        let url = Bundle.module.url(forResource: "activities", withExtension: "json")
            ?? Bundle.main.url(forResource: "activities", withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url) else {
            return []
        }
        do {
            return try JSONDecoder().decode([Activity].self, from: data)
        } catch {
            assertionFailure("Failed to decode activities.json: \(error)")
            return []
        }
    }
}

extension Activity.TimeOfDay {
    /// Bucket a clock time into a time-of-day slot, scaled to the user's workday.
    static func fromClock(
        minutesSinceMidnight m: Int,
        workdayStart: Int,
        workdayEnd: Int
    ) -> Activity.TimeOfDay {
        let span = max(1, workdayEnd - workdayStart)
        let pos = Double(m - workdayStart) / Double(span) // 0..1 over the workday
        switch pos {
        case ..<0.25: return .morning
        case ..<0.55: return .midday
        case ..<0.85: return .afternoon
        default: return .endOfDay
        }
    }
}
