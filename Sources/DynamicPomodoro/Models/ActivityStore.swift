import Foundation
import SwiftUI

/// Editable, persisted activity library.
/// Seeded from the bundled `activities.json` on first launch; thereafter the
/// user's edits/additions/deletions are stored in Application Support and are
/// the source of truth. Mutations are expected from the main thread (UI);
/// disk writes are dispatched to a background queue.
final class ActivityStore: ObservableObject {
    static let shared = ActivityStore()

    @Published private(set) var activities: [Activity] = []

    private let fileURL: URL
    private let ioQueue = DispatchQueue(label: "pomodoro.activitystore")

    private init() {
        let fm = FileManager.default
        let dir: URL
        if let supportDir = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            dir = supportDir.appendingPathComponent("DynamicPomodoro", isDirectory: true)
        } else {
            dir = fm.temporaryDirectory.appendingPathComponent("DynamicPomodoro", isDirectory: true)
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("user-activities.json")
        load()
    }

    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Activity].self, from: data) {
            self.activities = saved
        } else {
            // First run (or corrupted file): seed from bundled defaults.
            self.activities = ActivityLibrary.load()
            persist()
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
        activities.removeAll { $0.id == id }
        persist()
    }

    /// Discard all user edits and restore the bundled default library.
    func resetToDefaults() {
        activities = ActivityLibrary.load()
        persist()
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
}
