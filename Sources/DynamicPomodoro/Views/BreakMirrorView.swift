import SwiftUI

/// Small placeholder shown in the main window while the full-screen break overlay
/// is the primary UI. Mirrors timer state for users who click into the app window.
struct BreakMirrorView: View {
    @ObservedObject var timer: TimerController

    var body: some View {
        VStack(spacing: 16) {
            Text("Break in progress")
                .font(.headline)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1.5)

            if let activity = timer.currentActivity {
                Text(activity.name)
                    .font(.title2.weight(.semibold))
                Text(activity.instruction)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }

            Text(timer.remainingFormatted)
                .font(.system(size: 56, weight: .light, design: .monospaced))
                .monospacedDigit()
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
