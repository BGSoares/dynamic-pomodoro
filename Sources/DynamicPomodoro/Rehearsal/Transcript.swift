import Foundation

/// One user-visible moment of a rehearsed day. The transcript is the
/// product of a rehearsal: everything the user would have seen or heard,
/// in order, as text — so that whoever changed the code can read the day
/// the user is about to have (PURPOSE principle 9).
struct TranscriptEvent: Equatable {
    enum Kind {
        /// Something the simulated user does (clicks, holds, unlocks).
        case user
        /// Something the app puts on screen or in the room.
        case app
        /// The world changing around both (a call starting, the machine sleeping).
        case env
    }

    let at: Date
    let kind: Kind
    /// First line of the event. Continuation lines (an overlay card's
    /// contents) live in `detail`, rendered indented beneath.
    let text: String
    let detail: [String]

    init(at: Date, kind: Kind, text: String, detail: [String] = []) {
        self.at = at
        self.kind = kind
        self.text = text
        self.detail = detail
    }
}

enum TranscriptRenderer {
    /// Plain text, stable across platforms and time zones (the rehearsal
    /// clock is its own fixed calendar): fit for golden files and for
    /// reading in a terminal.
    static func render(
        header: [String],
        events: [TranscriptEvent],
        findings: [String],
        calendar: Calendar
    ) -> String {
        var lines: [String] = header.map { "# \($0)" }
        lines.append("")

        for event in events {
            let hms = clock(event.at, calendar: calendar)
            let prefix: String
            switch event.kind {
            case .user: prefix = "you:  "
            case .app: prefix = ""
            case .env: prefix = "env:  "
            }
            lines.append("\(hms)  \(prefix)\(event.text)")
            for d in event.detail {
                lines.append(String(repeating: " ", count: 10) + "| " + d)
            }
        }

        if !findings.isEmpty {
            lines.append("")
            lines.append("# INVARIANT FINDINGS (\(findings.count)) — each one is a bug the user would have met:")
            for f in findings {
                lines.append("# ✗ \(f)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func clock(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }
}
