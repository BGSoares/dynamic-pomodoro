import SwiftUI

/// Pre-session screen. Shows the suggested focus duration and a single action.
/// Daily stats footer is always shown (was a toggle in v1).
struct IdleView: View {
    @ObservedObject var timer: TimerEngine
    @State private var suggested: Int = 0
    @State private var stats: DailyStats = .empty
    private let refresh = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text("Ready")
                    .font(.system(size: 34, weight: .semibold))
                Text("Next session: \(suggested) min")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Button(action: { timer.startFocus() }) {
                Text("Start focus")
                    .font(.title3.weight(.medium))
                    .frame(minWidth: 160)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .overlay(alignment: .bottom) {
            DailyStatsFooter(stats: stats)
                .padding(.bottom, 20)
        }
        .onAppear {
            suggested = timer.suggestedFocusMinutes()
            stats = timer.dailyStats()
        }
        .onReceive(refresh) { _ in
            suggested = timer.suggestedFocusMinutes()
            stats = timer.dailyStats()
        }
    }
}

private struct DailyStatsFooter: View {
    let stats: DailyStats

    var body: some View {
        VStack(spacing: 2) {
            Text("\(formatDuration(stats.totalSeconds)) today")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text("\(formatPomos(stats.pomoCount)) · \(formatDuration(stats.focusSeconds)) focus")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    private func formatPomos(_ count: Double) -> String {
        let rounded = (count * 10).rounded() / 10
        let number: String
        if rounded == rounded.rounded() {
            number = String(format: "%.0f", rounded)
        } else {
            number = String(format: "%.1f", rounded)
        }
        let label = rounded == 1.0 ? "pomo" : "pomos"
        return "\(number) \(label)"
    }
}
