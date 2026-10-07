#if canImport(AppKit)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import DynamicPomodoro

/// Renders the app's windows to PNG files, on request – the one way to look
/// at the pixels from a session that has no screen to point a camera at
/// (PURPOSE principle 9: the glue is the thin remainder, and this is how it
/// gets seen). Skipped unless `DP_SNAPSHOT_DIR` names a directory to write
/// into:
///
///     DP_SNAPSHOT_DIR=/tmp/shots swift test --filter WindowSnapshotTests
///
/// Add `DP_SNAPSHOT_LOG_DIR=<directory holding a sessions.json>` to render
/// the stats pages over real (or fabricated) data; without it they render
/// empty. Each window is written twice, light and dark.
@Suite("WindowSnapshots", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["DP_SNAPSHOT_DIR"] != nil))
struct WindowSnapshotTests {
    private let outDir: URL
    private let log: SessionLogStore
    // Qualified: SwiftUI has a `Settings` scene of its own.
    private let settings: DynamicPomodoro.Settings

    init() throws {
        let env = ProcessInfo.processInfo.environment
        outDir = URL(fileURLWithPath: env["DP_SNAPSHOT_DIR"]!, isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let logDir = env["DP_SNAPSHOT_LOG_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("WindowSnapshots-\(UUID().uuidString)", isDirectory: true)
        log = SessionLogStore(directory: logDir)
        settings = DynamicPomodoro.Settings(defaults: UserDefaults(suiteName: "WindowSnapshots-\(UUID().uuidString)")!)
    }

    @Test @MainActor func statsTotals() throws {
        UserDefaults.standard.set("totals", forKey: "statsPage")
        try snapshot(StatsView(log: log, settings: settings), size: NSSize(width: 620, height: 520), name: "stats-totals")
    }

    @Test @MainActor func statsTimelineThisWeek() throws {
        UserDefaults.standard.set("timeline", forKey: "statsPage")
        try snapshot(StatsView(log: log, settings: settings), size: NSSize(width: 620, height: 520), name: "stats-timeline-this-week")
    }

    /// The timeline page as it reads on a Sunday evening: the week just
    /// finished, in full. Rendered through the page view directly so the
    /// snapshot can choose its own `now`.
    @Test @MainActor func statsTimelineFullWeek() throws {
        let calendar = Calendar.current
        let sunday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))!
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: sunday)!
        let now = calendar.date(byAdding: .hour, value: 23, to: thisWeek.start)!
            .addingTimeInterval(TimeInterval(6 * 86_400))
        let weeks = WeekTimeline.weeks(from: log.entries, calendar: calendar, now: now)
        let axis = WeekTimeline.axis(covering: weeks,
                                     workdayStartMinutes: settings.workdayStartMinutes,
                                     workdayEndMinutes: settings.workdayEndMinutes)
        try snapshot(
            WeekTimelineView(weeks: weeks, axis: axis, calendar: calendar)
                .padding(24)
                .frame(width: 620, height: 480, alignment: .topLeading),
            size: NSSize(width: 620, height: 480),
            name: "stats-timeline-full-week"
        )
    }

    @Test @MainActor func settingsWindow() throws {
        try snapshot(SettingsView(settings: settings), size: NSSize(width: 380, height: 474), name: "settings")
    }

    // MARK: - Machinery

    @MainActor
    private func snapshot<V: View>(_ view: V, size: NSSize, name: String) throws {
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            // Over the window background, as a window would show it – the
            // hosting view alone is transparent, and dark-mode text on a
            // transparent PNG reads as nothing at all.
            let host = NSHostingView(rootView: ZStack {
                Color(nsColor: .windowBackgroundColor)
                view
            })
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            // One turn of the run loop so SwiftUI lays out and `onAppear`
            // (which loads the log) has run before the pixels are read.
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            host.displayIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: outDir.appendingPathComponent("\(name)-\(suffix).png"))
        }
    }
}
#endif
