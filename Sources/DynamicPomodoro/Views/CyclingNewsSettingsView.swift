import SwiftUI

/// Manage RSS feed sources, trigger a manual refresh, reset to defaults.
struct CyclingNewsSettingsView: View {
    @ObservedObject var service: CyclingNewsService
    @Environment(\.dismiss) private var dismiss
    @State private var newFeedName: String = ""
    @State private var newFeedURL: String = ""
    @State private var addError: String?
    @State private var refreshTask: Task<Void, Never>?
    @State private var showResetConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Cycling news feeds")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()

            List {
                Section("Feeds") {
                    ForEach(service.feedSources) { feed in
                        feedRow(feed)
                    }
                }

                Section("Add a feed") {
                    TextField("Name (e.g. GCN)", text: $newFeedName)
                    TextField("RSS or Atom URL (https://…)", text: $newFeedURL)
                    if let err = addError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                    Button("Add feed") { addFeed() }
                        .disabled(newFeedURL.isEmpty || newFeedName.isEmpty)
                }
            }
            .listStyle(.inset)

            Divider()
            HStack {
                Button {
                    refreshTask?.cancel()
                    refreshTask = Task { await service.refresh(force: true) }
                } label: {
                    if service.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh now", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(service.isRefreshing)
                Spacer()
                Button("Reset to defaults") { showResetConfirm = true }
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 520, minHeight: 480)
        .confirmationDialog(
            "Reset feed sources to defaults?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) { service.resetFeedSourcesToDefaults() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Any custom feeds you added will be removed.")
        }
    }

    private func feedRow(_ feed: NewsFeedSource) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { feed.enabled },
                set: { service.setFeedEnabled(id: feed.id, enabled: $0) }
            ))
            .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(feed.name).font(.body.weight(.medium))
                Text(feed.url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(role: .destructive) {
                service.removeFeedSource(id: feed.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    private func addFeed() {
        addError = nil
        let trimmedURL = newFeedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = newFeedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            addError = "Please enter a valid http(s) URL."
            return
        }
        service.addFeedSource(name: trimmedName, url: url)
        newFeedName = ""
        newFeedURL = ""
    }
}
