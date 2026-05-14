import SwiftUI

/// The entire settings surface: workday hours and focus duration range.
/// No tabs, no sheets, no conditional sub-options.
struct SettingsView: View {
    @ObservedObject var settings: Settings

    var body: some View {
        Form {
            Section("Workday") {
                TimePicker(label: "Start",
                           minutes: Binding(
                            get: { settings.workdayStartMinutes },
                            set: { settings.workdayStartMinutes = min($0, settings.workdayEndMinutes - 60) }
                           ))
                TimePicker(label: "End",
                           minutes: Binding(
                            get: { settings.workdayEndMinutes },
                            set: { settings.workdayEndMinutes = max($0, settings.workdayStartMinutes + 60) }
                           ))
            }

            Section("Focus duration") {
                Stepper(
                    "Minimum: \(settings.minFocusMinutes) min",
                    value: Binding(
                        get: { settings.minFocusMinutes },
                        set: { settings.minFocusMinutes = min($0, settings.maxFocusMinutes - 5) }
                    ),
                    in: 5...60,
                    step: 5
                )
                Stepper(
                    "Maximum: \(settings.maxFocusMinutes) min",
                    value: Binding(
                        get: { settings.maxFocusMinutes },
                        set: { settings.maxFocusMinutes = max($0, settings.minFocusMinutes + 5) }
                    ),
                    in: 10...90,
                    step: 5
                )
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 360, minHeight: 260)
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
            Stepper(
                value: $minutes, in: 0...(23 * 60 + 45), step: 15
            ) {
                Text(TimeFormat.hhmm(minutes))
                    .monospacedDigit()
            }
            .labelsHidden()
            Text(TimeFormat.hhmm(minutes))
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
        }
    }
}
