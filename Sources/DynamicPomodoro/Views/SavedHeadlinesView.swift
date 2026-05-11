import SwiftUI

/// Read-only list of headlines the user pinned with "Save for later" during a
/// break. Tap to open in browser; swipe to remove.
struct SavedHeadlinesView: View {
    @ObservedObject var service: CyclingNewsService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Saved headlines")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()

            if service.saved.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("Nothing saved yet.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text("During a break, tap the save button on a cycling-news headline to read it later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                    Spacer()
                }
            } else {
                List {
                    ForEach(service.saved) { saved in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(saved.title)
                                .font(.body.weight(.medium))
                            HStack(spacing: 6) {
                                Text(saved.sourceName)
                                Text("·")
                                Text(saved.savedAt.formatted(date: .abbreviated, time: .shortened))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .onTapGesture { service.open(url: saved.url) }
                        .contextMenu {
                            Button("Open in browser") { service.open(url: saved.url) }
                            Button("Remove", role: .destructive) {
                                service.removeSavedHeadline(id: saved.id)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                service.removeSavedHeadline(id: saved.id)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 520, minHeight: 480)
    }
}
