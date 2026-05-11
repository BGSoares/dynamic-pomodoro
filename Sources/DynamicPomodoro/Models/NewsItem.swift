import Foundation

/// A single parsed item from a cycling-news RSS/Atom feed.
/// Bridged to `Activity` for break-time presentation; the original URL is
/// retained so the user can save it for later via `CyclingNewsService`.
struct NewsItem: Codable, Hashable, Identifiable {
    /// Stable id derived from the source GUID (or URL fallback) so dedup and
    /// "recently shown" tracking survive refreshes. Prefixed `news_` to avoid
    /// any collision with bundled activity ids.
    let id: String
    let title: String
    let summary: String
    let url: URL
    let publishedAt: Date
    let sourceID: String
    let sourceName: String

    /// Map an item to an `Activity` for the break overlay & manage-activities list.
    func asActivity() -> Activity {
        // Truncate summary so the overlay never has to render an essay.
        let clipped = NewsItem.clipSummary(summary)
        let instruction = clipped.isEmpty
            ? sourceName
            : "\(clipped) — \(sourceName)"
        return Activity(
            id: id,
            name: title,
            instruction: instruction,
            category: .cyclingNews,
            band: .short,
            energy: .gentle,
            suitableTimes: Activity.TimeOfDay.allCases
        )
    }

    static func makeID(from rawGUID: String?, link: URL) -> String {
        let key = (rawGUID?.isEmpty == false ? rawGUID! : link.absoluteString)
        // Cheap stable hash without pulling in CryptoKit; collisions across
        // thousands of cached items are vanishingly unlikely and a collision
        // just means one extra dedup hit.
        var hasher = Hasher()
        hasher.combine(key)
        let h = UInt64(bitPattern: Int64(hasher.finalize()))
        return "news_" + String(h, radix: 36)
    }

    static func clipSummary(_ s: String, limit: Int = 280) -> String {
        let stripped = stripHTML(s).trimmingCharacters(in: .whitespacesAndNewlines)
        guard stripped.count > limit else { return stripped }
        let head = stripped.prefix(limit)
        if let lastSpace = head.lastIndex(of: " ") {
            return String(head[..<lastSpace]) + "…"
        }
        return String(head) + "…"
    }

    /// Strip HTML tags and decode the small set of entities that show up in
    /// feed summaries. Not a sanitizer — input is rendered as plain text.
    static func stripHTML(_ s: String) -> String {
        // Drop tags.
        var out = ""
        out.reserveCapacity(s.count)
        var inTag = false
        for ch in s {
            if ch == "<" { inTag = true; continue }
            if ch == ">" { inTag = false; continue }
            if !inTag { out.append(ch) }
        }
        // Decode the handful of entities that actually appear in feeds.
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&nbsp;", " "), ("&hellip;", "…"), ("&mdash;", "—"),
            ("&ndash;", "–"), ("&rsquo;", "’"), ("&lsquo;", "‘"),
            ("&rdquo;", "”"), ("&ldquo;", "“"),
        ]
        for (entity, replacement) in entities {
            out = out.replacingOccurrences(of: entity, with: replacement)
        }
        return out
    }
}

/// A user-configured RSS/Atom feed source.
struct NewsFeedSource: Codable, Hashable, Identifiable {
    let id: String
    var name: String
    var url: URL
    var enabled: Bool

    static let defaults: [NewsFeedSource] = [
        NewsFeedSource(
            id: "cyclingnews",
            name: "Cyclingnews",
            url: URL(string: "https://www.cyclingnews.com/rss/")!,
            enabled: true
        ),
        NewsFeedSource(
            id: "road_cc",
            name: "road.cc",
            url: URL(string: "https://road.cc/rss")!,
            enabled: true
        ),
        NewsFeedSource(
            id: "rouleur",
            name: "Rouleur",
            url: URL(string: "https://rouleur.cc/blogs/the-rouleur-journal.atom")!,
            enabled: true
        ),
    ]
}

/// A headline the user pinned during a break to read later.
struct SavedHeadline: Codable, Hashable, Identifiable {
    let id: String          // NewsItem.id
    let title: String
    let url: URL
    let sourceName: String
    let savedAt: Date
}
