import SwiftUI

struct BreakCardView: View {
    @ObservedObject var timer: TimerController

    var body: some View {
        VStack(spacing: 20) {
            Text(timer.phase == .breakRunning ? "Break" : "Break ready")
                .font(.headline)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1.5)

            if let msg = timer.currentReminderMessage {
                Text(msg)
                    .font(.callout)
                    .italic()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            if let activity = timer.currentActivity {
                VStack(spacing: 10) {
                    Text(activity.name)
                        .font(.title2.weight(.semibold))
                    Text(activity.instruction)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary.opacity(0.85))
                        .padding(.horizontal, 12)
                    Text("\(activity.category.displayName) · \(timer.totalSeconds / 60) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No activity available. Take a break anyway.")
                    .foregroundStyle(.secondary)
            }

            if timer.phase == .breakRunning {
                TimerRing(progress: timer.progress, label: timer.remainingFormatted)
                    .frame(width: 180, height: 180)
                Button(role: .destructive) {
                    timer.skipBreak()
                } label: {
                    Text("End break").padding(.horizontal, 12)
                }
                .buttonStyle(.bordered)
            } else {
                HStack(spacing: 12) {
                    Button {
                        timer.startBreak()
                    } label: {
                        Text("Start").frame(minWidth: 80)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])

                    Button {
                        timer.swapActivity()
                    } label: {
                        Text("Swap").frame(minWidth: 80)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        timer.skipBreak()
                    } label: {
                        Text("Skip").frame(minWidth: 80)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
