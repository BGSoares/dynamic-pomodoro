import Foundation
import SwiftUI

/// Editable, persisted activity library.
/// Seeded from the bundled `activities.json` on first launch; thereafter the
/// user's edits/additions/deletions are stored in Application Support and are
/// the source of truth. Mutations are expected from the main thread (UI);
/// disk writes are dispatched to a background queue.
///
/// A sibling `seeded-bundled-ids.json` records every bundled activity id the
/// app has ever seeded for this user, so that bundled activities added in a
/// future release are merged in on next launch — and so that deletions of
/// bundled activities stay sticky across launches.
final class ActivityStore: ObservableObject {
    static let shared = ActivityStore()

    @Published private(set) var activities: [Activity] = []

    private let fileURL: URL
    private let seededIDsURL: URL
    private var seededBundledIDs: Set<String> = []
    private let ioQueue = DispatchQueue(label: "pomodoro.activitystore")

    private convenience init() {
        self.init(directory: Self.defaultDirectory())
    }

    internal init(directory: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("user-activities.json")
        self.seededIDsURL = directory.appendingPathComponent("seeded-bundled-ids.json")
        load()
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

    private func load() {
        let bundled = ActivityLibrary.load()

        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Activity].self, from: data) {
            // Pre-migration users have no seeded-ids file. Treat that as an
            // empty prior set so every currently-bundled id missing from the
            // user's file gets appended once. From this launch forward, the
            // seeded-ids file records what we've ever seeded so deletions of
            // bundled activities stay sticky.
            let priorSeeded = loadSeededIDs() ?? []
            let existing = Set(saved.map(\.id))
            let additions = bundled.filter {
                !priorSeeded.contains($0.id) && !existing.contains($0.id)
            }

            activities = saved + additions
            seededBundledIDs = priorSeeded.union(bundled.map(\.id))

            if !additions.isEmpty { persist() }
            if loadSeededIDs() != seededBundledIDs { persistSeededIDs() }
        } else {
            // True first launch (or corrupted user file): seed from bundle.
            activities = bundled
            seededBundledIDs = Set(bundled.map(\.id))
            persist()
            persistSeededIDs()
        }
    }

    func add(_ activity: Activity) {
        activities.append(activity)
        persist()
    }

    func update(_ activity: Activity) {
        guard let idx = activities.firstIndex(where: { $0.id == activity.id }) else { return }
        activities[idx] = activity
        persist()
    }

    func delete(id: String) {
        // Intentionally does NOT mutate seededBundledIDs: keeping the id in
        // the seeded set is what makes a deletion stick across launches.
        activities.removeAll { $0.id == id }
        persist()
    }

    /// Discard all user edits and restore the bundled default library.
    func resetToDefaults() {
        let bundled = ActivityLibrary.load()
        activities = bundled
        seededBundledIDs = Set(bundled.map(\.id))
        persist()
        persistSeededIDs()
    }

    private func loadSeededIDs() -> Set<String>? {
        guard let data = try? Data(contentsOf: seededIDsURL),
              let arr = try? JSONDecoder().decode([String].self, from: data)
        else { return nil }
        return Set(arr)
    }

    private func persist() {
        let snapshot = activities
        let url = fileURL
        ioQueue.async {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? enc.encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func persistSeededIDs() {
        let snapshot = seededBundledIDs
        let url = seededIDsURL
        ioQueue.async {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? enc.encode(Array(snapshot).sorted()) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
