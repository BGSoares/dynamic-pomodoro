import SwiftUI

/// Pre-session screen. Shows the suggested focus duration and a single action.
/// Daily stats footer is always shown (was a toggle in v1).
struct IdleView: View {
    @ObservedObject var timer: TimerEngine
    @State private var suggested: Int = 0
    @State private var stats: DailyStats = .empty
    @State private var showFeedback: Bool = false
    @State private var feedbackQuestion: FeedbackQuestion? = nil
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
            maybeShowFeedback()
        }
        .onReceive(refresh) { _ in
            suggested = timer.suggestedFocusMinutes()
            stats = timer.dailyStats()
        }
        .sheet(isPresented: $showFeedback, onDismiss: { FeedbackGate.markPrompted() }) {
            FeedbackSheet(question: feedbackQuestion) { response in
                FeedbackStore.shared.append(response)
            }
        }
    }

    /// Trigger the once-per-user feedback prompt on a "moment of success" —
    /// the user has just landed back on Idle after enough completed sessions
    /// to have an opinion worth collecting.
    private func maybeShowFeedback() {
        guard !showFeedback else { return }
        let completed = SessionLogStore.shared.completedFocusCount()
        guard FeedbackGate.shouldShow(completedFocusCount: completed) else { return }
        feedbackQuestion = FeedbackQuestionLoader.load()
        // Small delay so the Idle view has time to render under the sheet —
        // otherwise the sheet appears against a blank window for a frame.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            showFeedback = true
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
        let number = rounded == rounded.rounded() ? String(format: "%.0f", rounded) : String(format: "%.1f", rounded)
        let label = rounded == 1.0 ? "pomo" : "pomos"
        return "\(number) \(label)"
    }
}
