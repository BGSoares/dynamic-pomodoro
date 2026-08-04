import SwiftUI

/// Shown only if a window happens to already be open while a break is owed
/// but a call is live — .breakPending never opens a window on its own
/// (SPEC_LOOP_CONTINUITY.md §4.2). The manual escape valve (for false
/// positives, or a call the mic outlives) lives in the status menu's
/// "Start break now" item now, not here — principle 7 forbids fronting a
/// window for it, so the override "moves to the status menu" (§4.2) rather
/// than staying duplicated in both places.
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

            Text("Use “Start break now” in the menu bar to start it early.")
                .font(.caption)
                .foregroundStyle(.tertiary)
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
