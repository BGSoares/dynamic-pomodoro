import XCTest
@testable import DynamicPomodoro

/// Persistence-layer tests for `JSONArrayStore` (via `SessionLogStore`).
/// The store is shared by feedback.json too, so the corrupt-file behaviour
/// here covers that path as well.
final class SessionLogStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionLogStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// A malformed sessions.json must be preserved on disk under a
    /// `.corrupt-<ts>` suffix instead of being silently overwritten by
    /// the next save() — the user's history is the whole point of the file.
    func testLoadOfCorruptFileRenamesItAndFallsBackToEmpty() throws {
        let fileURL = tempDir.appendingPathComponent("sessions.json")
        try Data("{ not valid json".utf8).write(to: fileURL)

        let store = SessionLogStore(directory: tempDir)

        XCTAssertTrue(store.entries.isEmpty, "expected fallback to empty array on decode failure")

        let contents = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        let backups = contents.filter { $0.hasPrefix("sessions.json.corrupt-") }
        XCTAssertEqual(backups.count, 1, "expected exactly one .corrupt-<ts> backup, got: \(contents)")

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fileURL.path),
            "original sessions.json should have been moved aside"
        )
    }

    /// A missing file is not corrupt — load() returns silently, no backup created.
    func testLoadOfMissingFileDoesNothing() throws {
        let store = SessionLogStore(directory: tempDir)
        XCTAssertTrue(store.entries.isEmpty)

        let contents = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertTrue(
            contents.filter { $0.hasPrefix("sessions.json.corrupt-") }.isEmpty,
            "no backup file should be created for a missing log"
        )
    }
}
