import AppKit
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
        .onAppear { refreshData() }
        .onReceive(refresh) { _ in refreshData() }
        // The 30s timer above can be throttled by App Nap while the app is
        // backgrounded, so refresh as soon as the app regains focus —
        // otherwise a session left open across hours shows a stale duration.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshData()
        }
    }

    private func refreshData() {
        suggested = timer.suggestedFocusMinutes()
        stats = timer.dailyStats()
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
        let h = seconds / 3600, m = (seconds % 3600) / 60
        return h == 0 ? "\(m)m" : m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private func formatPomos(_ count: Double) -> String {
        let v = (count * 10).rounded() / 10
        let n = v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%.1f", v)
        return "\(n) pomo\(v == 1 ? "" : "s")"
    }
}
