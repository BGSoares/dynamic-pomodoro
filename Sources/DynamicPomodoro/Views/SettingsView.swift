import SwiftUI

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
                CurvePreviewView(settings: settings)
                    .padding(.top, 8)
            }

            Section("Break activities") {
                ForEach(Activity.Category.allCases, id: \.self) { cat in
                    Toggle(cat.displayName, isOn: Binding(
                        get: { !settings.disabledCategories.contains(cat.rawValue) },
                        set: { enabled in
                            if enabled { settings.disabledCategories.remove(cat.rawValue) }
                            else { settings.disabledCategories.insert(cat.rawValue) }
                        }
                    ))
                }
            }

            Section("Notifications") {
                Toggle("Sound on notification", isOn: $settings.soundEnabled)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 560)
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
