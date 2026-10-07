import SwiftUI

/// The entire settings surface: workday hours, the focus-duration curve's
/// three anchors, and whether a break pauses media. No tabs, no sheets, no
/// conditional sub-options.
struct SettingsView: View {
    @ObservedObject var settings: Settings

    private var workdayStartBinding: Binding<Int> {
        .init(get: { settings.workdayStartMinutes },
              set: { settings.workdayStartMinutes = min($0, settings.workdayEndMinutes - 60) })
    }
    private var workdayEndBinding: Binding<Int> {
        .init(get: { settings.workdayEndMinutes },
              set: { settings.workdayEndMinutes = max($0, settings.workdayStartMinutes + 60) })
    }
    private var minFocusStartBinding: Binding<Int> {
        .init(get: { settings.minFocusStartMinutes },
              set: { settings.minFocusStartMinutes = min($0, settings.maxFocusMinutes - 5) })
    }
    private var minFocusEndBinding: Binding<Int> {
        .init(get: { settings.minFocusEndMinutes },
              set: { settings.minFocusEndMinutes = min($0, settings.maxFocusMinutes - 5) })
    }
    private var maxFocusBinding: Binding<Int> {
        .init(get: { settings.maxFocusMinutes },
              set: { settings.maxFocusMinutes = max($0, max(settings.minFocusStartMinutes, settings.minFocusEndMinutes) + 5) })
    }

    var body: some View {
        Form {
            Section("Workday") {
                TimePicker(label: "Start", minutes: workdayStartBinding)
                TimePicker(label: "End", minutes: workdayEndBinding)
            }
            // Listed in the order the day runs: the floor you start from, the
            // peak in the middle, the floor you end on.
            Section {
                Stepper("Minimum at start: \(settings.minFocusStartMinutes) min",
                        value: minFocusStartBinding, in: 5...60, step: 1)
                Stepper("Maximum: \(settings.maxFocusMinutes) min",
                        value: maxFocusBinding, in: 10...90, step: 1)
                Stepper("Minimum at end: \(settings.minFocusEndMinutes) min",
                        value: minFocusEndBinding, in: 5...60, step: 1)
            } header: {
                Text("Focus duration")
            } footer: {
                Text("Sessions rise from the start minimum to the maximum at the middle of the workday, then fall to the end minimum.")
            }
            Section("Breaks") {
                Toggle("Pause playing media when a break starts", isOn: $settings.pauseMediaOnBreak)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 360, minHeight: 454)
        .padding(.bottom, 8)
    }
}

private struct TimePicker: View {
    let label: String
    @Binding var minutes: Int

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Stepper("", value: $minutes, in: 0...(23 * 60 + 45), step: 15)
                .labelsHidden()
            Text(TimeFormat.hhmm(minutes))
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
        }
    }
}
