import AppKit
import SwiftUI

/// Pre-session screen. Shows the suggested focus duration and a single action.
/// Daily stats footer is always shown (was a toggle in v1).
struct IdleView: View {
    @ObservedObject var timer: TimerEngine
    @State private var suggested: Int = 0
    @State private var stats: DailyStats = .empty
    @State private var showFeedback: Bool = false
    @State private var feedbackQuestion: FeedbackQuestion? = nil
    @State private var showReminderThumb: Bool = false
    private let refresh = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    /// UserDefaults key for the one-shot reminder-quote thumbs probe.
    /// Once set ("up" or "down"), the widget is never shown again.
    private static let reminderThumbKey = "reminderMsgThumb"

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
            VStack(spacing: 8) {
                if showReminderThumb {
                    ReminderThumbProbe { up in
                        UserDefaults.standard.set(up ? "up" : "down", forKey: Self.reminderThumbKey)
                        withAnimation { showReminderThumb = false }
                    }
                }
                DailyStatsFooter(stats: stats)
            }
            .padding(.bottom, 20)
        }
        .onAppear {
            refreshData()
            maybeShowFeedback()
            checkReminderThumb()
        }
        .onReceive(refresh) { _ in refreshData() }
        // The 30s timer above can be throttled by App Nap while the app is
        // backgrounded, so refresh as soon as the app regains focus —
        // otherwise a session left open across hours shows a stale duration.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshData()
        }
        .sheet(isPresented: $showFeedback, onDismiss: { FeedbackGate.markPrompted() }) {
            FeedbackSheet(question: feedbackQuestion) { response in
                FeedbackStore.shared.append(response)
            }
        }
    }

    private func refreshData() {
        suggested = timer.suggestedFocusMinutes()
        stats = timer.dailyStats()
    }

    /// Trigger the once-per-user feedback prompt on a "moment of success" —
    /// the user has just landed back on Idle after enough completed sessions
    /// to have an opinion worth collecting.
    private func maybeShowFeedback() {
        guard !showFeedback, FeedbackGate.shouldShow(completedFocusCount: SessionLogStore.shared.completedFocusCount()) else { return }
        feedbackQuestion = FeedbackQuestionLoader.load()
        // Small delay so the Idle view has time to render under the sheet —
        // otherwise the sheet appears against a blank window for a frame.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showFeedback = true }
    }

    /// Show the reminder-quote thumbs probe after the first completed break,
    /// but only once (UserDefaults gate).
    private func checkReminderThumb() {
        showReminderThumb = UserDefaults.standard.string(forKey: Self.reminderThumbKey) == nil
            && SessionLogStore.shared.entries.contains { $0.kind == .breakCompleted }
    }
}

/// One-shot probe. Remove permanently once rating is read and logged in USER_RESEARCH.md.
private struct ReminderThumbProbe: View {
    let onRate: (Bool) -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text("The short italic line at the top of the full-screen break overlay (e.g. *“Rest is when your brain consolidates what you just learned.”*) — is it useful?")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)

            HStack(spacing: 20) {
                Button("👍") { onRate(true) }
                    .buttonStyle(.plain)
                Button("👎") { onRate(false) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.07))
        )
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
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private func formatPomos(_ count: Double) -> String {
        let r = (count * 10).rounded() / 10
        let n = r.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(r)) : String(format: "%.1f", r)
        return "\(n) \(r == 1 ? "pomo" : "pomos")"
    }
}
