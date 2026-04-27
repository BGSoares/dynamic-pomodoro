import SwiftUI

/// Editor for the break activity library — list with edit / delete / add /
/// reset-to-defaults. Shown as a sheet from SettingsView.
struct ManageActivitiesView: View {
    @ObservedObject var store: ActivityStore
    @Environment(\.dismiss) private var dismiss

    @State private var editing: EditTarget?
    @State private var pendingDeleteID: String?
    @State private var showResetConfirm = false

    /// Discriminator for the editor sheet — `Identifiable` so `.sheet(item:)` works.
    private enum EditTarget: Identifiable {
        case existing(Activity)
        case new

        var id: String {
            switch self {
            case .existing(let a): return a.id
            case .new: return "__new__"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            activitiesList
            Divider()
            footer
        }
        .frame(minWidth: 520, minHeight: 560)
        .sheet(item: $editing) { target in
            switch target {
            case .existing(let a):
                ActivityEditorView(initial: a, store: store)
            case .new:
                ActivityEditorView(initial: nil, store: store)
            }
        }
        .confirmationDialog(
            "Reset to default activities?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) { store.resetToDefaults() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your custom activities and edits will be removed.")
        }
    }

    private var header: some View {
        HStack {
            Text("Break activities")
                .font(.headline)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var activitiesList: some View {
        List {
            ForEach(Activity.Category.allCases, id: \.self) { category in
                let inCategory = store.activities.filter { $0.category == category }
                if !inCategory.isEmpty {
                    Section(category.displayName) {
                        ForEach(inCategory) { activity in
                            ActivityRow(activity: activity)
                                .contentShape(Rectangle())
                                .onTapGesture { editing = .existing(activity) }
                                .contextMenu {
                                    Button("Edit") { editing = .existing(activity) }
                                    Button("Delete", role: .destructive) {
                                        pendingDeleteID = activity.id
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        pendingDeleteID = activity.id
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .alert(
            "Delete this activity?",
            isPresented: Binding(
                get: { pendingDeleteID != nil },
                set: { if !$0 { pendingDeleteID = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteID { store.delete(id: id) }
                pendingDeleteID = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteID = nil }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                editing = .new
            } label: {
                Label("Add activity", systemImage: "plus")
            }

            Spacer()

            Button("Reset to defaults") {
                showResetConfirm = true
            }
            .foregroundStyle(.secondary)

            Spacer()

            Text("\(store.activities.count) total")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct ActivityRow: View {
    let activity: Activity

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.name)
                    .font(.body.weight(.medium))
                Text(activity.instruction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 4) {
                Text(activity.band == .short ? "Short" : "Medium")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(activity.energy.displayName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Form for creating or editing a single Activity.
struct ActivityEditorView: View {
    let initial: Activity?
    @ObservedObject var store: ActivityStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var instruction: String = ""
    @State private var category: Activity.Category = .stretch
    @State private var band: Activity.DurationBand = .short
    @State private var energy: Activity.Energy = .gentle
    @State private var times: Set<Activity.TimeOfDay> = Set(Activity.TimeOfDay.allCases)

    private var isNew: Bool { initial == nil }
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !times.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text(isNew ? "New activity" : "Edit activity")
                    .font(.headline)
                Spacer()
                Button(isNew ? "Add" : "Save") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            Form {
                Section("Name") {
                    TextField("e.g. Neck rolls", text: $name)
                }

                Section("Instruction") {
                    TextEditor(text: $instruction)
                        .font(.body)
                        .frame(minHeight: 90)
                }

                Section("Classification") {
                    Picker("Category", selection: $category) {
                        ForEach(Activity.Category.allCases, id: \.self) { c in
                            Text(c.displayName).tag(c)
                        }
                    }
                    Picker("Duration", selection: $band) {
                        ForEach(Activity.DurationBand.allCases, id: \.self) { b in
                            Text(b.displayName).tag(b)
                        }
                    }
                    Picker("Energy", selection: $energy) {
                        ForEach(Activity.Energy.allCases, id: \.self) { e in
                            Text(e.displayName).tag(e)
                        }
                    }
                }

                Section("Suitable times of day") {
                    ForEach(Activity.TimeOfDay.allCases, id: \.self) { t in
                        Toggle(t.displayName, isOn: Binding(
                            get: { times.contains(t) },
                            set: { isOn in
                                if isOn { times.insert(t) } else { times.remove(t) }
                            }
                        ))
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 480, minHeight: 600)
        .onAppear { populate() }
    }

    private func populate() {
        guard let a = initial else { return }
        name = a.name
        instruction = a.instruction
        category = a.category
        band = a.band
        energy = a.energy
        times = Set(a.suitableTimes)
    }

    private func save() {
        let activity = Activity(
            id: initial?.id ?? "custom_\(UUID().uuidString.lowercased())",
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            instruction: instruction.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            band: band,
            energy: energy,
            suitableTimes: Activity.TimeOfDay.allCases.filter { times.contains($0) }
        )
        if isNew {
            store.add(activity)
        } else {
            store.update(activity)
        }
    }
}
