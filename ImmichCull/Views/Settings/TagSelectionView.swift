import SwiftUI

/// Picks which tags mean "already culled". A `Picker` can only select one
/// thing, so this is a plain list of checkmark rows.
struct TagSelectionView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var tags: [ImmichTag] = []
    @State private var isLoading = true
    @State private var didLoadTags = false
    @State private var loadError: String?

    var body: some View {
        List {
            if let loadError {
                Section {
                    Text(loadError)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(tags) { tag in
                    TagSelectionRowView(
                        name: tag.name,
                        isSelected: settings.checkedTagNames.contains(tag.name),
                        toggle: { toggle(tag.name) }
                    )
                }
                // A tag can be selected and then deleted on the server; keep it
                // visible so it can be deselected rather than silently stuck.
                ForEach(orphanedNames, id: \.self) { name in
                    TagSelectionRowView(
                        name: name,
                        isSelected: true,
                        isMissing: true,
                        toggle: { toggle(name) }
                    )
                }
            } footer: {
                Text("Assets carrying any of these tags count as already culled.")
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
            } else if tags.isEmpty && orphanedNames.isEmpty && loadError == nil {
                ContentUnavailableView(
                    "No Tags",
                    systemImage: "tag",
                    description: Text("Tags you create in Immich will appear here.")
                )
            }
        }
        .navigationTitle("Already culled tags")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("tagSelectionList")
        .task { await loadTags() }
    }

    /// Only meaningful once the server has actually told us what exists. On a
    /// failed (or never-attempted) load `tags` is empty, and deriving from that
    /// would label every selected tag as deleted from the server.
    private var orphanedNames: [String] {
        guard didLoadTags else { return [] }
        let known = Set(tags.map(\.name))
        return settings.checkedTagNames.filter { !known.contains($0) }
    }

    private func toggle(_ name: String) {
        if let index = settings.checkedTagNames.firstIndex(of: name) {
            settings.checkedTagNames.remove(at: index)
        } else {
            settings.checkedTagNames.append(name)
        }
    }

    private func loadTags() async {
        guard let client = settings.client else {
            loadError = String(localized: "Connect to your Immich server to choose tags.")
            isLoading = false
            return
        }
        do {
            tags = try await client.tags().sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            didLoadTags = true
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
