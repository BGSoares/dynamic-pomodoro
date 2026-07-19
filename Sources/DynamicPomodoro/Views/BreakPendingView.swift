import SwiftUI

/// Shown in the main window while a break is owed but a call is live.
/// The break starts on its own when the call ends; the button is the manual
/// escape valve (for false positives, or leaving a call the mic outlives).
struct BreakPendingView: View {
    @ObservedObject var timer: TimerEngine

    var body: some View {
        VStack(spacing: 16) {
            Text("Focus done")
                .font(.headline)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1.5)

            Text("You're on a call")
                .font(.title2.weight(.semibold))

            Text("The break starts on its own when the call ends.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let since = timer.state.pendingSince {
                Text("Waiting \(waitingText(since: since))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            Button("Start break now") { timer.startPendingBreak() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func waitingText(since: Date) -> String {
        let m = max(0, Int(Date().timeIntervalSince(since)) / 60)
        return m == 0 ? "less than a minute" : "\(m) min"
    }
}
