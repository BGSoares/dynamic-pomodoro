import SwiftUI

struct FocusView: View {
    @ObservedObject var timer: TimerEngine
    @State private var confirmingAbandon = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Focus")
                .font(.headline)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1.5)

            TimerRing(progress: timer.progress, label: timer.remainingFormatted)
                .frame(width: 240, height: 240)

            Button(role: .destructive) {
                confirmingAbandon = true
            } label: {
                Text("Abandon session")
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .confirmationDialog(
                "Abandon this session?",
                isPresented: $confirmingAbandon,
                titleVisibility: .visible
            ) {
                Button("Abandon", role: .destructive) { timer.abandonFocus() }
                Button("Continue", role: .cancel) {}
            } message: {
                Text("Interrupted sessions are discarded — you'll start fresh next time.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

/// Minimal ring progress indicator used by both focus and break timers.
struct TimerRing: View {
    let progress: Double
    let label: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(0.0001, min(1, progress)))
                .stroke(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: progress)

            Text(label)
                .font(.system(size: 44, weight: .medium, design: .monospaced))
                .monospacedDigit()
        }
    }
}
