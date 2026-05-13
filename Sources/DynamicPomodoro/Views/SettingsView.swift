import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject private var calendarService = CalendarService.shared
    @ObservedObject private var activityStore = ActivityStore.shared
    @ObservedObject private var cyclingNews = CyclingNewsService.shared
    @State private var showingActivityManager = false
    @State private var showingCyclingNewsManager = false
    @State private var showingSavedHeadlines = false

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

                HStack {
                    Button("Manage activities…") {
                        showingActivityManager = true
                    }
                    Spacer()
                    Text("\(activityStore.activities.count) total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Cycling News") {
                Toggle("Show cycling news during breaks", isOn: $settings.cyclingNewsEnabled)
                if settings.cyclingNewsEnabled {
                    Toggle("Open headlines in browser when saved", isOn: $settings.openHeadlinesInBrowser)
                    HStack {
                        Button("Manage feeds…") { showingCyclingNewsManager = true }
                        Spacer()
                        Button("Saved headlines…") { showingSavedHeadlines = true }
                        Text("\(cyclingNews.saved.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let last = cyclingNews.lastRefreshAt {
                        Text("Last refresh: \(last.formatted(date: .abbreviated, time: .shortened)) · \(cyclingNews.items.count) cached")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No headlines fetched yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let err = cyclingNews.lastRefreshError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Text("Cycling news headlines are fetched from RSS feeds and shown read-only during breaks. Tap to save for later; the article opens in your browser after the break.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                Toggle("Sound on notification", isOn: $settings.soundEnabled)
                Toggle("Pause media when break starts", isOn: $settings.pauseMediaOnBreak)
            }

            Section("Security") {
                Toggle("Lock screen when break ends", isOn: $settings.lockScreenAfterBreak)
                Text("If you're not back at your desk when the break finishes, the screen locks so a passer-by can't see your session. Skipping the break doesn't lock — you're clearly present.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Display") {
                Toggle("Show daily totals on idle screen", isOn: $settings.showDailyStats)
                Toggle("Compact menu bar timer (e.g. \"6 m\")", isOn: $settings.compactMenuBarTimer)
            }

            Section("iPhone / Calendar sync") {
                Toggle("Mirror breaks to Calendar", isOn: Binding(
                    get: { settings.calendarSyncEnabled },
                    set: { newValue in
                        if newValue {
                            calendarService.requestAccess { granted in
                                settings.calendarSyncEnabled = granted
                                if granted, settings.calendarIdentifier == nil {
                                    settings.calendarIdentifier = calendarService.suggestedCalendarIdentifier
                                }
                            }
                        } else {
                            settings.calendarSyncEnabled = false
                        }
                    }
                ))

                if settings.calendarSyncEnabled && calendarService.authorized {
                    Picker("Calendar", selection: Binding(
                        get: { settings.calendarIdentifier ?? "" },
                        set: { settings.calendarIdentifier = $0.isEmpty ? nil : $0 }
                    )) {
                        ForEach(calendarService.writableCalendars) { cal in
                            Text("\(cal.title)  ·  \(cal.sourceTitle)").tag(cal.id)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if calendarService.authorizationDenied {
                    Text("Calendar access was denied. Enable it in System Settings → Privacy & Security → Calendars.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text("Creates a Calendar event for each break. Pick an iCloud calendar and the end time appears on your iPhone lock screen and Apple Watch — handy when you walk away from your desk.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 560)
        .padding(.bottom, 8)
        .onAppear { calendarService.refreshAuthorizationStatus() }
        .sheet(isPresented: $showingActivityManager) {
            ManageActivitiesView(store: activityStore)
        }
        .sheet(isPresented: $showingCyclingNewsManager) {
            CyclingNewsSettingsView(service: cyclingNews)
        }
        .sheet(isPresented: $showingSavedHeadlines) {
            SavedHeadlinesView(service: cyclingNews)
        }
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
