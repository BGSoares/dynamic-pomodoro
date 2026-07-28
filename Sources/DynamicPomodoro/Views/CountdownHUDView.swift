import SwiftUI

/// Floating countdown card shown on a qualifying unlock (SPEC_UNLOCK_AUTOSTART.md §5).
/// Driven entirely by the service's published countdown state — no
/// knowledge of the notification, the gate, or its own panel lifecycle.
struct CountdownHUDView: View {
    @ObservedObject var service: UnlockAutoStartService
    /// The panel handles its own alpha fade; this drives the "subtle SwiftUI
    /// scale 0.96→1" half of the entrance §5.1 asks for.
    @State private var appeared = false

    /// Drains from 1 to 0 as the countdown runs out.
    private var progress: Double {
        guard service.totalSeconds > 0 else { return 0 }
        return Double(service.secondsRemaining) / Double(service.totalSeconds)
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: max(0.0001, min(1, progress)))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: progress)

                Text("\(service.secondsRemaining)")
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 96, height: 96)

            VStack(spacing: 4) {
                Text("Focus starts in \(service.secondsRemaining)s")
                    .font(.headline)
                Text("Esc or click the menu bar icon to cancel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .scaleEffect(appeared ? 1 : 0.96)
        .onAppear {
            withAnimation(.easeOut(duration: 0.25)) { appeared = true }
        }
    }
}
