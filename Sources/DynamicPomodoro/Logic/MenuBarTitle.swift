import Foundation

/// The status item's title — the most-seen surface of the app, extracted
/// from the AppKit layer so it is decided in pure code the rehearsal can
/// replay (PURPOSE principle 9). `main.swift` renders exactly this string.
enum MenuBarTitle {
    /// Leading space pads the text off the dolphin icon.
    static func text(for state: PomodoroState, suggestedMinutes: @autoclosure () -> Int) -> String {
        switch state.phase {
        case .idle: " Start \(suggestedMinutes())m"
        case .focus: " F \(state.remainingFormatted)"
        case .breakPending: " B …"
        case .breakRunning: " B \(state.remainingFormatted)"
        }
    }
}
