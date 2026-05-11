import XCTest
@testable import DynamicPomodoro

final class ActivityStoreMigrationTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivityStoreMigrationTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
    }

    private var userFileURL: URL { tempDir.appendingPathComponent("user-activities.json") }
    private var seededIDsURL: URL { tempDir.appendingPathComponent("seeded-bundled-ids.json") }

    private func waitForDiskWrites() {
        // ActivityStore persists via a private serial DispatchQueue.async; a
        // brief sleep lets pending writes flush before we inspect disk.
        Thread.sleep(forTimeInterval: 0.1)
    }

    private func makeStore() -> ActivityStore {
        let store = ActivityStore(directory: tempDir)
        waitForDiskWrites()
        return store
    }

    private func readSeededIDs() -> Set<String>? {
        guard let data = try? Data(contentsOf: seededIDsURL),
              let arr = try? JSONDecoder().decode([String].self, from: data)
        else { return nil }
        return Set(arr)
    }

    // MARK: - Tests

    func testFirstLaunchSeedsAllBundled() {
        let bundled = ActivityLibrary.load()
        XCTAssertFalse(bundled.isEmpty, "Bundled activities should not be empty")

        let store = makeStore()

        XCTAssertEqual(store.activities.count, bundled.count)
        XCTAssertEqual(Set(store.activities.map(\.id)), Set(bundled.map(\.id)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: userFileURL.path))
        XCTAssertEqual(readSeededIDs(), Set(bundled.map(\.id)))
    }

    func testOldAppMigrationAddsMissingBundled() throws {
        let bundled = ActivityLibrary.load()
        let bundledMinusInspiration = bundled.filter { $0.category != .inspiration }
        XCTAssertLessThan(bundledMinusInspiration.count, bundled.count,
                          "Bundle should include some inspiration activities")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        try enc.encode(bundledMinusInspiration).write(to: userFileURL, options: .atomic)
        XCTAssertFalse(FileManager.default.fileExists(atPath: seededIDsURL.path))

        let store = makeStore()

        let inspirationIDs = bundled.filter { $0.category == .inspiration }.map(\.id)
        let storeIDs = Set(store.activities.map(\.id))
        for id in inspirationIDs {
            XCTAssertTrue(storeIDs.contains(id), "Expected migrated id \(id) to be present")
        }
        XCTAssertEqual(readSeededIDs(), Set(bundled.map(\.id)))
    }

    func testDeletionPreservedAcrossRelaunch() {
        let store1 = makeStore()
        let inspirationID = store1.activities.first(where: { $0.category == .inspiration })?.id
        XCTAssertNotNil(inspirationID)
        store1.delete(id: inspirationID!)
        waitForDiskWrites()

        let store2 = makeStore()
        XCTAssertFalse(store2.activities.contains(where: { $0.id == inspirationID }),
                       "Deleted bundled activity should not be re-added on relaunch")
        XCTAssertTrue(readSeededIDs()?.contains(inspirationID!) ?? false,
                      "Deleted id must remain in the seeded set")
    }

    func testIdempotentRelaunch() {
        let store1 = makeStore()
        let firstCount = store1.activities.count
        let firstIDs = store1.activities.map(\.id)

        let store2 = makeStore()
        XCTAssertEqual(store2.activities.count, firstCount)
        XCTAssertEqual(store2.activities.map(\.id), firstIDs)

        let store3 = makeStore()
        XCTAssertEqual(store3.activities.count, firstCount)
        XCTAssertEqual(store3.activities.map(\.id), firstIDs)
    }

    func testResetToDefaultsRefreshesSeededIDs() {
        let store = makeStore()
        let someID = store.activities.first!.id
        store.delete(id: someID)
        waitForDiskWrites()

        store.resetToDefaults()
        waitForDiskWrites()

        let bundled = ActivityLibrary.load()
        XCTAssertEqual(Set(store.activities.map(\.id)), Set(bundled.map(\.id)))
        XCTAssertEqual(readSeededIDs(), Set(bundled.map(\.id)))
    }

    func testCorruptedSeededIDsFileFallsBack() throws {
        let bundled = ActivityLibrary.load()
        let subset = bundled.filter { $0.category != .inspiration }

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try JSONEncoder().encode(subset).write(to: userFileURL, options: .atomic)
        try Data("not valid json".utf8).write(to: seededIDsURL, options: .atomic)

        let store = makeStore()

        let storeIDs = Set(store.activities.map(\.id))
        let inspirationIDs = bundled.filter { $0.category == .inspiration }.map(\.id)
        for id in inspirationIDs {
            XCTAssertTrue(storeIDs.contains(id),
                          "Corrupted seeded-ids file should fall back to old-app migration")
        }
        XCTAssertEqual(readSeededIDs(), Set(bundled.map(\.id)))
    }
}
