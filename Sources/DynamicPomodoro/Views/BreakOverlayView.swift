import SwiftUI

/// Full-screen break view hosted in a shielding-level NSPanel.
/// This is THE break UI — no separate prompt, no Start button; the overlay's
/// fade-in is the prep, and the timer runs for its full duration.
/// Skip requires a 15-second hold (intentional friction, not a lockout).
struct BreakOverlayView: View {
    @ObservedObject var timer: TimerEngine

    /// Caption under the skip button. Switches to a one-line nudge from
    /// `SkipNudgeMessages` while the user is mid-hold, then reverts on release.
    @State private var skipNudge: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.overlayPurple, .overlayNavy],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Subtle radial vignette in the centre
            RadialGradient(
                colors: [Color.white.opacity(0.04), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 500
            )
            .allowsHitTesting(false)

            VStack(spacing: 44) {
                Spacer()

                if let msg = timer.state.currentReminderMessage {
                    Text(msg)
                        .font(.title3)
                        .italic()
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 80)
                        .frame(maxWidth: 900)
                }

                if let activity = timer.state.currentActivity {
                    VStack(spacing: 20) {
                        Text(activity.name)
                            .font(.system(size: 64, weight: .semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 80)
                            .frame(maxWidth: 1100)
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
        // Ignore safe area at the root so the VStack centerline matches the
        // window centerline. Without this, an asymmetric dock (left side, or
        // any auto-hide config) inset the foreground content while the
        // background still filled the screen, drifting the timer to the right.
        .ignoresSafeArea()
    }

    private var countdownRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 8)

            Circle()
                .trim(from: 0, to: max(0.0001, 1 - timer.state.progress))
                .stroke(
                    LinearGradient(
                        colors: [.ringPink, .ringCyan, .ringGold],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.4), value: timer.state.progress)

            Text(timer.state.remainingFormatted)
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HoldToSkipButton(
                onComplete: { timer.skipBreak() },
                onHoldStateChange: { skipNudge = $0 ? SkipNudgeMessages.pool.randomElement() : nil }
            )
            Text(skipNudge ?? "Hold to skip")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .animation(.easeInOut(duration: 0.2), value: skipNudge)
        }
    }
}

// MARK: - Palette

private extension Color {
    // Background: app-icon palette (dark purple → navy)
    static let overlayPurple = Color(red: 0.05, green: 0.03, blue: 0.13)
    static let overlayNavy   = Color(red: 0.07, green: 0.10, blue: 0.26)
    // Countdown ring
    static let ringPink      = Color(red: 1.00, green: 0.00, blue: 0.43)
    static let ringCyan      = Color(red: 0.00, green: 0.85, blue: 1.00)
    static let ringGold      = Color(red: 1.00, green: 0.84, blue: 0.04)
}
