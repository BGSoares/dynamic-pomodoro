import SwiftUI

/// Pre-session screen. Shows the suggested focus duration and a single action.
struct IdleView: View {
    @ObservedObject var timer: TimerController
    @ObservedObject var settings: Settings
    @State private var suggested: Int = 0
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
        .onAppear { suggested = timer.suggestedFocusMinutes() }
        .onReceive(refresh) { _ in suggested = timer.suggestedFocusMinutes() }
    }
}
