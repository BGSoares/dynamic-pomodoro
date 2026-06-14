import SwiftUI

/// Circular button that fills a progress ring as the user holds it.
/// Triggers onComplete after the full hold duration; cancels smoothly on early release.
struct HoldToSkipButton: View {
    private static let holdDuration: TimeInterval = 15.0
    var onComplete: () -> Void
    /// Called with `true` the moment the hold begins, and `false` when an
    /// in-progress hold is released early. Not called when the hold completes
    /// (the parent view dismisses on completion).
    var onHoldStateChange: ((Bool) -> Void)? = nil

    @State private var progress: Double = 0
    @State private var tickTimer: Timer?

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.white.opacity(0.95),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.05), value: progress)
            Image(systemName: "xmark")
                .foregroundStyle(.white.opacity(0.7 - 0.4 * progress))
                .font(.system(size: 22, weight: .medium))
        }
        .frame(width: 64, height: 64)
        .scaleEffect(progress > 0 ? 1.08 : 1.0)
        .animation(.easeOut(duration: 0.15), value: progress > 0)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard progress < 1.0, tickTimer == nil else { return }
                    startTicker()
                    onHoldStateChange?(true)
                }
                .onEnded { _ in
                    guard tickTimer != nil else { return }
                    stopTicker()
                    if progress < 1.0 { withAnimation(.easeOut(duration: 0.25)) { progress = 0 } }
                    onHoldStateChange?(false)
                }
        )
        .onDisappear { stopTicker() }
    }

    private func startTicker() {
        stopTicker()
        let start = Date()
        let t = Timer(timeInterval: 0.03, repeats: true) { t in
            let p = min(Date().timeIntervalSince(start) / Self.holdDuration, 1.0)
            progress = p
            if p >= 1.0 {
                t.invalidate()
                tickTimer = nil
                onComplete()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        tickTimer = t
    }

    private func stopTicker() {
        tickTimer?.invalidate()
        tickTimer = nil
    }
}
