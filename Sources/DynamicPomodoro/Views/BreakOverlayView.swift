import SwiftUI

/// Full-screen break view hosted in a screenSaver-level NSWindow.
/// This is THE break UI — no separate prompt, no Start button; the overlay's
/// fade-in is the prep, and the timer runs for its full duration.
/// Skip requires a 2-second hold (intentional friction, not a lockout).
struct BreakOverlayView: View {
    @ObservedObject var timer: TimerController

    var body: some View {
        ZStack {
            // Match the app-icon palette: calming dark purple→navy
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.03, blue: 0.13),
                    Color(red: 0.07, green: 0.10, blue: 0.26),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Subtle radial vignette in the centre
            RadialGradient(
                colors: [Color.white.opacity(0.04), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 500
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 44) {
                Spacer()

                if let msg = timer.currentReminderMessage {
                    Text(msg)
                        .font(.title3)
                        .italic()
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 80)
                        .frame(maxWidth: 900)
                }

                if let activity = timer.currentActivity {
                    VStack(spacing: 20) {
                        Text(activity.name)
                            .font(.system(size: 64, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(activity.instruction)
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(.white.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 120)
                            .frame(maxWidth: 1000)
                    }
                } else {
                    Text("Take a break")
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(.white)
                }

                countdownRing
                    .frame(width: 220, height: 220)

                Spacer()

                controls
                    .padding(.bottom, 48)
            }
        }
    }

    private var countdownRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 8)

            Circle()
                .trim(from: 0, to: max(0.0001, 1 - timer.progress))
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 1.00, green: 0.00, blue: 0.43), // hot pink
                            Color(red: 0.00, green: 0.85, blue: 1.00), // cyan
                            Color(red: 1.00, green: 0.84, blue: 0.04), // gold
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.4), value: timer.progress)

            Text(timer.remainingFormatted)
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 28) {
                HoldToSkipButton(onComplete: { timer.skipBreak() })
                SwapButton { timer.swapActivity() }
            }
            Text("Hold to skip")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.35))
        }
    }
}

// MARK: - Hold-to-skip

/// Circular button that fills a progress ring as the user holds it.
/// Triggers onComplete after the full hold duration; cancels smoothly on early release.
private struct HoldToSkipButton: View {
    let holdDuration: TimeInterval = 30.0
    var onComplete: () -> Void

    @State private var progress: Double = 0
    @State private var tickTimer: Timer?
    @State private var holdStart: Date?
    @State private var completed = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.white.opacity(0.85),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.05), value: progress)
            Image(systemName: "xmark")
                .foregroundStyle(.white.opacity(0.7))
                .font(.system(size: 22, weight: .medium))
        }
        .frame(width: 64, height: 64)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !completed, holdStart == nil else { return }
                    holdStart = Date()
                    startTicker()
                }
                .onEnded { _ in
                    cancelIfNotComplete()
                }
        )
        .onDisappear { stopTicker() }
    }

    private func startTicker() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { t in
            guard let start = holdStart else { t.invalidate(); return }
            let elapsed = Date().timeIntervalSince(start)
            let p = min(elapsed / holdDuration, 1.0)
            DispatchQueue.main.async { progress = p }
            if p >= 1.0 {
                t.invalidate()
                completed = true
                holdStart = nil
                DispatchQueue.main.async { onComplete() }
            }
        }
    }

    private func cancelIfNotComplete() {
        guard !completed else { return }
        stopTicker()
        holdStart = nil
        withAnimation(.easeOut(duration: 0.25)) { progress = 0 }
    }

    private func stopTicker() {
        tickTimer?.invalidate()
        tickTimer = nil
    }
}

// MARK: - Swap

private struct SwapButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 3)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.white.opacity(0.7))
                    .font(.system(size: 22, weight: .medium))
            }
            .frame(width: 64, height: 64)
        }
        .buttonStyle(.plain)
    }
}
