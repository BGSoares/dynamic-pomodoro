import SwiftUI

/// First-run setup (§6). Six short steps + curve preview + start.
struct OnboardingView: View {
    @ObservedObject var settings: Settings
    var onFinish: () -> Void
    @State private var step = 0
    @State private var showBreakWhy = false

    private let totalSteps = 7

    var body: some View {
        VStack(spacing: 24) {
            ProgressView(value: Double(step + 1), total: Double(totalSteps))
                .progressViewStyle(.linear)
                .frame(maxWidth: 320)

            Group {
                switch step {
                case 0: welcome
                case 1: workdayStart
                case 2: workdayEnd
                case 3: breakPhilosophy
                case 4: peakFocus
                case 5: minFocus
                case 6: preview
                default: welcome
                }
            }
            .frame(minHeight: 260)

            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .buttonStyle(.bordered)
                } else {
                    Spacer().frame(width: 1)
                }
                Spacer()
                Button(step == totalSteps - 1 ? "Start first session" : "Next") {
                    if step < totalSteps - 1 {
                        step += 1
                    } else {
                        settings.onboardingComplete = true
                        onFinish()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
            }
            .frame(maxWidth: 400)
        }
        .padding(32)
        .frame(minWidth: 520, minHeight: 480)
    }

    private var welcome: some View {
        VStack(spacing: 12) {
            Text("Dynamic Pomodoro")
                .font(.largeTitle.weight(.semibold))
            Text("Focus sessions that match your energy across the day, with active breaks.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var workdayStart: some View {
        OnboardStep(title: "When does your workday start?",
                    subtitle: "The curve ramps up from here.") {
            VStack(spacing: 12) {
                Text(TimeFormat.hhmm(settings.workdayStartMinutes))
                    .font(.system(size: 48, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                Stepper("", value: Binding(
                    get: { settings.workdayStartMinutes },
                    set: { settings.workdayStartMinutes = min($0, settings.workdayEndMinutes - 60) }
                ), in: 0...(23 * 60 + 45), step: 15)
                .labelsHidden()
            }
        }
    }

    private var workdayEnd: some View {
        OnboardStep(title: "When does it end?",
                    subtitle: "The curve ramps back down to this time.") {
            VStack(spacing: 12) {
                Text(TimeFormat.hhmm(settings.workdayEndMinutes))
                    .font(.system(size: 48, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                Stepper("", value: Binding(
                    get: { settings.workdayEndMinutes },
                    set: { settings.workdayEndMinutes = max($0, settings.workdayStartMinutes + 60) }
                ), in: 0...(23 * 60 + 45), step: 15)
                .labelsHidden()
            }
        }
    }

    private var peakFocus: some View {
        OnboardStep(title: "Peak focus duration",
                    subtitle: "The longest session you'll do mid-day.") {
            VStack(spacing: 12) {
                Text("\(settings.maxFocusMinutes) min")
                    .font(.system(size: 48, weight: .medium))
                Stepper("", value: Binding(
                    get: { settings.maxFocusMinutes },
                    set: { settings.maxFocusMinutes = max($0, settings.minFocusMinutes + 5) }
                ), in: 15...90, step: 5)
                .labelsHidden()
            }
        }
    }

    private var minFocus: some View {
        OnboardStep(title: "Minimum focus duration",
                    subtitle: "Used for the first session of the day, and outside work hours.") {
            VStack(spacing: 12) {
                Text("\(settings.minFocusMinutes) min")
                    .font(.system(size: 48, weight: .medium))
                Stepper("", value: Binding(
                    get: { settings.minFocusMinutes },
                    set: { settings.minFocusMinutes = min($0, settings.maxFocusMinutes - 5) }
                ), in: 5...60, step: 5)
                .labelsHidden()
            }
        }
    }

    private var preview: some View {
        VStack(spacing: 16) {
            Text("Here's your day")
                .font(.title.weight(.semibold))
            Text("Hover the curve to see what sessions will look like across the day.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            CurvePreviewView(settings: settings)
                .padding(.horizontal, 8)
        }
    }

    private var breakPhilosophy: some View {
        VStack(spacing: 18) {
            Text("Breaks aren't optional here")
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)

            if showBreakWhy {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Skipping a break borrows from your next focus session, with interest.",
                          systemImage: "arrow.uturn.backward.circle")
                    Label("A break taken now prevents the long, foggy hour at 4pm.",
                          systemImage: "clock.badge.exclamationmark")
                    Label("Your best ideas arrive when the prefrontal cortex stops gripping the problem.",
                          systemImage: "lightbulb")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440, alignment: .leading)
            } else {
                VStack(spacing: 10) {
                    Text("Most timers let you skip with a tap. This one makes you hold for 15 seconds — not to lock you out, but to make sure you mean it.")
                    Text("Each break gets one suggested activity. You can swap it. You can ignore it. But the timer runs its full length, because that's what makes the next session work.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            }

            Button(showBreakWhy ? "Got it" : "Why?") {
                showBreakWhy.toggle()
            }
            .buttonStyle(.borderless)
            .font(.callout)
            .foregroundStyle(.tint)
        }
    }
}

private struct OnboardStep<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text(title).font(.title.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            content()
                .padding(.top, 8)
        }
    }
}
