import Foundation
import Combine
#if canImport(AppKit)
import AppKit
#endif

/// Orchestrates the cycling-news pipeline:
///  - Owns the feed-source list (persisted) with sensible defaults.
///  - Fetches enabled feeds concurrently and merges results into a deduped,
///    capped, time-evicted cache on disk.
///  - Exposes the cache as `[Activity]` for break-time selection.
///  - Owns the "Saved for later" headline list and `open(_:)` integration.
///
/// Mutations to `@Published` state happen on the main thread (assert at call
/// sites; the orchestrator hops `URLSession` results back to the main queue
/// before mutating); disk writes hop to a background queue (same pattern as
/// `ActivityStore`).
final class CyclingNewsService: ObservableObject {
    static let shared = CyclingNewsService()

    // MARK: - Tuning constants
    /// Cap the cache so a noisy feed can't bloat selection or disk.
    static let maxCacheItems = 40
    /// Drop items older than this on every refresh.
    static let cacheTTL: TimeInterval = 7 * 24 * 60 * 60
    /// Minimum time between automatic refreshes (manual button bypasses this).
    static let autoRefreshInterval: TimeInterval = 60 * 60
    /// Debounce window for the launch-time refresh.
    static let launchRefreshDebounce: TimeInterval = 30 * 60

    // MARK: - Published state
    @Published private(set) var items: [NewsItem] = []
    @Published private(set) var saved: [SavedHeadline] = []
    @Published private(set) var feedSources: [NewsFeedSource]
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var isRefreshing: Bool = false
    @Published private(set) var lastRefreshError: String?

    // MARK: - Storage
    private let cacheURL: URL
    private let savedURL: URL
    private let feedSourcesURL: URL
    private let lastRefreshKey = "cyclingNews.lastRefreshAt"
    private let ioQueue = DispatchQueue(label: "pomodoro.cyclingnews")

    // MARK: - Init

    private convenience init() {
        self.init(directory: CyclingNewsService.defaultDirectory())
    }

    internal init(directory: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        self.cacheURL = directory.appendingPathComponent("cycling-news-cache.json")
        self.savedURL = directory.appendingPathComponent("cycling-news-saved.json")
        self.feedSourcesURL = directory.appendingPathComponent("cycling-news-feeds.json")
        self.feedSources = []
        self.feedSources = loadFeedSources() ?? NewsFeedSource.defaults
        self.items = loadCache() ?? []
        self.saved = loadSaved() ?? []
        if let ts = UserDefaults.standard.object(forKey: lastRefreshKey) as? Double {
            self.lastRefreshAt = Date(timeIntervalSince1970: ts)
        }
    }

    private static func defaultDirectory() -> URL {
        let fm = FileManager.default
        if let supportDir = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            return supportDir.appendingPathComponent("DynamicPomodoro", isDirectory: true)
        }
        return fm.temporaryDirectory.appendingPathComponent("DynamicPomodoro", isDirectory: true)
    }

    // MARK: - Activity bridge

    /// Cached headlines mapped to `Activity` for `ActivitySelector` /
    /// `ManageActivitiesView`. Returns `[]` when no items are cached so the
    /// selector falls through to the rest of the library.
    var activities: [Activity] {
        items.map { $0.asActivity() }
    }

    /// Lookup the URL for a news activity by its id (used by the break
    /// overlay's Save button).
    func newsItem(activityID: String) -> NewsItem? {
        items.first(where: { $0.id == activityID })
    }

    // MARK: - Refresh

    /// Refresh enabled feeds. `force == false` returns early if a refresh
    /// happened recently (debounced by `launchRefreshDebounce`); the user-
    /// triggered "Refresh now" button always passes `force: true`.
    func refresh(force: Bool = false) async {
        if !force, let last = lastRefreshAt,
           Date().timeIntervalSince(last) < Self.launchRefreshDebounce {
            return
        }
        await performRefresh()
    }

    private func performRefresh() async {
        let enabled = await MainActor.run { () -> [NewsFeedSource] in
            self.isRefreshing = true
            self.lastRefreshError = nil
            return self.feedSources.filter(\.enabled)
        }
        guard !enabled.isEmpty else {
            await MainActor.run { self.isRefreshing = false }
            return
        }

        // Failures per-feed are tolerated so one slow/dead source doesn't
        // poison the batch.
        let fetched: [[NewsItem]] = await withTaskGroup(of: [NewsItem].self) { group in
            for source in enabled {
                group.addTask {
                    do {
                        return try await RSSFetcher.fetch(source: source)
                    } catch {
                        return []
                    }
                }
            }
            var results: [[NewsItem]] = []
            for await batch in group { results.append(batch) }
            return results
        }
        let merged = fetched.flatMap { $0 }

        await MainActor.run {
            let nothingFetched = merged.isEmpty
            self.items = Self.mergeAndPrune(existing: self.items, incoming: merged)
            self.persistCache()
            let now = Date()
            self.lastRefreshAt = now
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: self.lastRefreshKey)
            self.isRefreshing = false
            self.lastRefreshError = nothingFetched
                ? "No headlines fetched. Check your network or feed URLs."
                : nil
        }
    }

    /// Pure merge: combine existing + incoming, dedupe by id (incoming wins),
    /// drop anything older than the TTL, then keep the newest `maxCacheItems`.
    static func mergeAndPrune(
        existing: [NewsItem],
        incoming: [NewsItem],
        now: Date = Date(),
        ttl: TimeInterval = cacheTTL,
        cap: Int = maxCacheItems
    ) -> [NewsItem] {
        var byID: [String: NewsItem] = [:]
        for item in existing { byID[item.id] = item }
        for item in incoming { byID[item.id] = item }  // incoming wins
        let cutoff = now.addingTimeInterval(-ttl)
        return byID.values
            .filter { $0.publishedAt >= cutoff }
            .sorted { $0.publishedAt > $1.publishedAt }
            .prefix(cap)
            .map { $0 }
    }

    // MARK: - Feed sources

    func addFeedSource(name: String, url: URL) {
        let id = "user_" + UUID().uuidString.lowercased()
        feedSources.append(NewsFeedSource(id: id, name: name, url: url, enabled: true))
        persistFeedSources()
    }

    func removeFeedSource(id: String) {
        feedSources.removeAll { $0.id == id }
        persistFeedSources()
    }

    func setFeedEnabled(id: String, enabled: Bool) {
        guard let idx = feedSources.firstIndex(where: { $0.id == id }) else { return }
        feedSources[idx].enabled = enabled
        persistFeedSources()
    }

    func resetFeedSourcesToDefaults() {
        feedSources = NewsFeedSource.defaults
        persistFeedSources()
    }

    // MARK: - Saved headlines

    /// Save a headline (deduped). If `openInBrowser` is true, also open the URL
    /// immediately — used when Settings has "Open headlines in browser" on.
    func saveHeadline(activityID: String, openInBrowser: Bool = false) {
        guard let item = newsItem(activityID: activityID) else { return }
        if !saved.contains(where: { $0.id == item.id }) {
            saved.insert(
                SavedHeadline(
                    id: item.id,
                    title: item.title,
                    url: item.url,
                    sourceName: item.sourceName,
                    savedAt: Date()
                ),
                at: 0
            )
            persistSaved()
        }
        if openInBrowser {
            open(url: item.url)
        }
    }

    func removeSavedHeadline(id: String) {
        saved.removeAll { $0.id == id }
        persistSaved()
    }

    func open(url: URL) {
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }

    // MARK: - Test seam

    /// Test-only entry point: inject cache items without a network refresh.
    /// Kept `internal` so `@testable import` can reach it from the test
    /// target while production callers still see `items` as read-only.
    internal func _replaceCacheForTesting(_ newItems: [NewsItem]) {
        self.items = newItems
    }

    // MARK: - Persistence

    private func loadCache() -> [NewsItem]? { decode([NewsItem].self, from: cacheURL) }
    private func loadSaved() -> [SavedHeadline]? { decode([SavedHeadline].self, from: savedURL) }
    private func loadFeedSources() -> [NewsFeedSource]? { decode([NewsFeedSource].self, from: feedSourcesURL) }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(T.self, from: data)
    }

    private func persistCache() {
        writeJSON(items, to: cacheURL)
    }

    private func persistSaved() {
        writeJSON(saved, to: savedURL)
    }

    private func persistFeedSources() {
        writeJSON(feedSources, to: feedSourcesURL)
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) {
        let snapshot = value
        ioQueue.async {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            enc.dateEncodingStrategy = .iso8601
            if let data = try? enc.encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
