import Foundation
import Testing
@testable import DynamicPomodoro

/// Persistence-layer tests for `JSONArrayStore` (via `SessionLogStore`).
/// The store is shared by feedback.json too, so the behaviour here covers
/// that path as well.
@Suite("SessionLogStore")
final class SessionLogStoreTests {
    private let tempDir: URL

    init() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionLogStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func entry(kind: SessionLogEntry.Kind, day: Int, hour: Int, activity: String? = nil) -> SessionLogEntry {
        var c = DateComponents()
        c.year = 2025; c.month = 6; c.day = day; c.hour = hour
        let start = Calendar.current.date(from: c)!
        return SessionLogEntry(kind: kind, from: start, to: start.addingTimeInterval(20 * 60), minutes: 20, activity: activity)
    }

    // MARK: - Round trip

    /// What one store writes, a fresh store on the same directory reads back
    /// identically — the whole persistence contract in one test.
    @Test func appendedEntriesSurviveAReload() {
        let first = SessionLogStore(directory: tempDir)
        let e1 = entry(kind: .focusCompleted, day: 15, hour: 9)
        let e2 = entry(kind: .breakCompleted, day: 15, hour: 10, activity: "neck_rolls")
        first.append(e1)
        first.append(e2)

        let reloaded = SessionLogStore(directory: tempDir)
        #expect(reloaded.entries == [e1, e2])
    }

    // MARK: - Corruption handling

    /// A malformed sessions.json must be preserved on disk under a
    /// `.corrupt-<ts>` suffix instead of being silently overwritten by
    /// the next save() — the user's history is the whole point of the file.
    @Test func loadOfCorruptFileRenamesItAndFallsBackToEmpty() throws {
        let fileURL = tempDir.appendingPathComponent("sessions.json")
        try Data("{ not valid json".utf8).write(to: fileURL)

        let store = SessionLogStore(directory: tempDir)

        #expect(store.entries.isEmpty, "expected fallback to empty array on decode failure")

        let contents = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        let backups = contents.filter { $0.hasPrefix("sessions.json.corrupt-") }
        #expect(backups.count == 1, "expected exactly one .corrupt-<ts> backup, got: \(contents)")

        #expect(!FileManager.default.fileExists(atPath: fileURL.path),
                "original sessions.json should have been moved aside")
    }

    /// An unreadable-but-present file is treated like a corrupt one: moved
    /// aside, never clobbered by the next save.
    @Test func loadOfUnreadableFilePreservesItAsBackup() throws {
        let fileURL = tempDir.appendingPathComponent("sessions.json")
        try Data("[]".utf8).write(to: fileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fileURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path) }

        let store = SessionLogStore(directory: tempDir)
        #expect(store.entries.isEmpty)

        let contents = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        let backups = contents.filter { $0.hasPrefix("sessions.json.corrupt-") }
        #expect(backups.count == 1, "expected the unreadable file preserved as backup, got: \(contents)")
        // Restore permissions on the backup so deinit can delete the temp dir.
        if let backup = backups.first {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: tempDir.appendingPathComponent(backup).path
            )
        }
    }

    /// A missing file is not corrupt — load() returns silently, no backup created.
    @Test func loadOfMissingFileDoesNothing() throws {
        let store = SessionLogStore(directory: tempDir)
        #expect(store.entries.isEmpty)

        let contents = (try? FileManager.default.contentsOfDirectory(atPath: tempDir.path)) ?? []
        #expect(contents.filter { $0.hasPrefix("sessions.json.corrupt-") }.isEmpty,
                "no backup file should be created for a missing log")
    }

    // MARK: - First-session-of-day rule

    @Test func hasCompletedFocusTodayIgnoresAbandonedAttempts() {
        let store = SessionLogStore(directory: tempDir)
        var c = DateComponents()
        c.year = 2025; c.month = 6; c.day = 15; c.hour = 13
        let today = Calendar.current.date(from: c)!

        #expect(!store.hasCompletedFocusToday(now: today))

        store.append(entry(kind: .focusAbandoned, day: 15, hour: 9))
        #expect(!store.hasCompletedFocusToday(now: today),
                "an abandoned attempt must not consume the day's warm-up")

        store.append(entry(kind: .focusCompleted, day: 14, hour: 9))
        #expect(!store.hasCompletedFocusToday(now: today),
                "yesterday's completion does not count for today")

        store.append(entry(kind: .focusCompleted, day: 15, hour: 10))
        #expect(store.hasCompletedFocusToday(now: today))
    }
}
