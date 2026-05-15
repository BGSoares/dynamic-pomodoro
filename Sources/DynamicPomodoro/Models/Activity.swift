import Foundation

struct Activity: Identifiable, Codable, Hashable {
    enum Category: String, Codable, CaseIterable {
        case stretch, breathwork
        case eyeRest = "eye_rest"
        case walk, mindfulness, hydration, inspiration
    }

    enum DurationBand: String, Codable, CaseIterable {
        case short, medium
    }

    enum Energy: String, Codable, CaseIterable {
        case gentle, moderate, active
    }

    enum TimeOfDay: String, Codable, CaseIterable {
        case morning, midday, afternoon
        case endOfDay = "end_of_day"
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
    /// Load the bundled activities.json. See `BundleResource` for why this
    /// can't use `Bundle.module` directly.
    static func load() -> [Activity] {
        let url = BundleResource.url(forResource: "activities", withExtension: "json")
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

extension Activity {
    /// The full activity library, loaded once from the bundled JSON.
    /// Source of truth — no per-user persistence, no in-app editing.
    /// To customise: edit `Resources/activities.json` and rebuild.
    static let defaultLibrary: [Activity] = ActivityLibrary.load()
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
