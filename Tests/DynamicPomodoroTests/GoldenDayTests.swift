import Foundation
import Testing
@testable import DynamicPomodoro

/// The two scripted days, frozen as checked-in transcripts. Any change to
/// what the user would see — a reworded notification, a different card, a
/// shifted lock — fails here and shows up as a reviewable diff against
/// `Fixtures/*.txt`. That diff *is* the review artifact: an intentional
/// change re-records the fixture and ships the new day for reading in the
/// PR; an unintentional one gets caught before the user meets it.
///
/// Re-record after an intentional user-visible change with:
///
///     DP_REHEARSAL_RECORD=1 swift test --filter GoldenDayTests
///
/// then read the fixture diff end to end — that is the point of it.
@Suite("GoldenDays")
struct GoldenDayTests {

    @Test func canonicalDayMatchesItsGolden() throws {
        try compare(script: .canonical, fixture: "canonical-day.txt")
    }

    @Test func meetingsDayMatchesItsGolden() throws {
        try compare(script: .meetings, fixture: "meetings-day.txt")
    }

    // MARK: - Machinery

    private func compare(script: RehearsalScript, fixture: String) throws {
        let transcript = DayRehearsal.run(script: script).renderedTranscript()
        let url = fixtureURL(fixture)

        if ProcessInfo.processInfo.environment["DP_REHEARSAL_RECORD"] != nil {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(transcript.utf8).write(to: url)
            Issue.record("recorded \(fixture) — re-run without DP_REHEARSAL_RECORD, and read the diff")
            return
        }

        guard let data = FileManager.default.contents(atPath: url.path),
              let golden = String(data: data, encoding: .utf8) else {
            Issue.record("missing fixture \(fixture) — record it with DP_REHEARSAL_RECORD=1")
            return
        }

        if transcript != golden {
            let diff = firstDivergence(golden: golden, current: transcript)
            Issue.record("""
            the \(script.name) day no longer matches its golden transcript.
            \(diff)
            If this change to what the user sees is intentional: re-record with
            DP_REHEARSAL_RECORD=1 swift test --filter GoldenDayTests, and read the diff.
            """)
        }
    }

    /// Fixtures live next to the test source (found via #filePath), so they
    /// need no resource-bundle plumbing and the recorder can write them.
    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(name)
    }

    private func firstDivergence(golden: String, current: String) -> String {
        let g = golden.components(separatedBy: "\n")
        let c = current.components(separatedBy: "\n")
        for i in 0..<max(g.count, c.count) {
            let gl = i < g.count ? g[i] : "<end of golden>"
            let cl = i < c.count ? c[i] : "<end of transcript>"
            if gl != cl {
                return "first divergence at line \(i + 1):\n  golden : \(gl)\n  current: \(cl)"
            }
        }
        return "same lines, different bytes (line endings?)"
    }
}
