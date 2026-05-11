import XCTest
@testable import DynamicPomodoro

final class CyclingNewsServiceTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CyclingNewsServiceTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
    }

    private func item(
        id: String,
        published: Date = Date(),
        source: String = "test"
    ) -> NewsItem {
        NewsItem(
            id: id,
            title: id,
            summary: "summary for \(id)",
            url: URL(string: "https://example.com/\(id)")!,
            publishedAt: published,
            sourceID: source,
            sourceName: source
        )
    }

    // MARK: - Merge / prune

    func testMergeDedupesByID() {
        let existing = [item(id: "a"), item(id: "b")]
        let incoming = [item(id: "b"), item(id: "c")]
        let merged = CyclingNewsService.mergeAndPrune(existing: existing, incoming: incoming)
        XCTAssertEqual(Set(merged.map(\.id)), Set(["a", "b", "c"]))
    }

    func testMergeEvictsOlderThanTTL() {
        let now = Date()
        let old = item(id: "old", published: now.addingTimeInterval(-10 * 24 * 60 * 60)) // 10 days
        let fresh = item(id: "fresh", published: now)
        let merged = CyclingNewsService.mergeAndPrune(
            existing: [old],
            incoming: [fresh],
            now: now
        )
        XCTAssertEqual(merged.map(\.id), ["fresh"])
    }

    func testMergeRespectsCap() {
        let now = Date()
        let many = (0..<60).map { i in
            item(id: "\(i)", published: now.addingTimeInterval(-Double(i)))
        }
        let merged = CyclingNewsService.mergeAndPrune(
            existing: [],
            incoming: many,
            now: now,
            cap: 40
        )
        XCTAssertEqual(merged.count, 40)
        // Newest first.
        XCTAssertEqual(merged.first?.id, "0")
    }

    // MARK: - Saved headlines

    func testSaveHeadlineDedupes() {
        let service = CyclingNewsService(directory: tempDir)
        service._replaceCacheForTesting([item(id: "x")])
        service.saveHeadline(activityID: "x")
        service.saveHeadline(activityID: "x")
        XCTAssertEqual(service.saved.count, 1)
    }

    func testSaveHeadlineIgnoresUnknownID() {
        let service = CyclingNewsService(directory: tempDir)
        service.saveHeadline(activityID: "does-not-exist")
        XCTAssertEqual(service.saved.count, 0)
    }

    func testRemoveSavedHeadline() {
        let service = CyclingNewsService(directory: tempDir)
        service._replaceCacheForTesting([item(id: "x")])
        service.saveHeadline(activityID: "x")
        XCTAssertEqual(service.saved.count, 1)
        service.removeSavedHeadline(id: "x")
        XCTAssertEqual(service.saved.count, 0)
    }

    // MARK: - Feed sources

    func testFeedSourcesSeedWithDefaultsOnFirstLaunch() {
        let service = CyclingNewsService(directory: tempDir)
        XCTAssertEqual(service.feedSources.count, NewsFeedSource.defaults.count)
    }

    func testAddAndRemoveFeed() {
        let service = CyclingNewsService(directory: tempDir)
        let before = service.feedSources.count
        service.addFeedSource(name: "GCN", url: URL(string: "https://example.com/gcn.rss")!)
        XCTAssertEqual(service.feedSources.count, before + 1)
        let id = service.feedSources.last!.id
        service.removeFeedSource(id: id)
        XCTAssertEqual(service.feedSources.count, before)
    }

    func testToggleFeedEnabled() {
        let service = CyclingNewsService(directory: tempDir)
        let firstID = service.feedSources.first!.id
        service.setFeedEnabled(id: firstID, enabled: false)
        XCTAssertEqual(service.feedSources.first(where: { $0.id == firstID })?.enabled, false)
    }

    // MARK: - Activity bridge

    func testActivitiesMapPreservesIDs() {
        let service = CyclingNewsService(directory: tempDir)
        service._replaceCacheForTesting([item(id: "a"), item(id: "b")])
        let activities = service.activities
        XCTAssertEqual(activities.count, 2)
        XCTAssertEqual(Set(activities.map(\.id)), Set(["a", "b"]))
        XCTAssertTrue(activities.allSatisfy { $0.category == .cyclingNews })
    }
}

