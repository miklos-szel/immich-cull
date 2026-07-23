import SwiftUI

struct TagsSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var tags: [ImmichTag] = []

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle("Offer already-culled photos again", isOn: $settings.reOfferChecked)
            } footer: {
                Text("Tags below mark a photo as already reviewed so it's skipped next run.")
            }

            Section("Treat these tags as already culled") {
                if tagNames.isEmpty {
                    Text("No tags on this server yet.").foregroundStyle(.secondary)
                }
                ForEach(tagNames, id: \.self) { name in
                    Button {
                        toggleChecked(name)
                    } label: {
                        HStack {
                            Text(name)
                            Spacer()
                            Image(systemName: settings.checkedTagNames.contains(name) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(settings.checkedTagNames.contains(name) ? .green : .secondary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Mark culled photos with") {
                Picker("Tag", selection: $settings.markTagName) {
                    ForEach(markOptions, id: \.self) { Text($0).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { await loadTags() }
    }

    private var tagNames: [String] {
        // Server tags plus any locally-selected names no longer on the server.
        let server = tags.map(\.name)
        let orphans = settings.checkedTagNames.filter { !server.contains($0) }
        return (server + orphans).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var markOptions: [String] {
        var names = tags.map(\.name)
        if !settings.markTagName.isEmpty && !names.contains(settings.markTagName) {
            names.insert(settings.markTagName, at: 0)
        }
        return names
    }

    private func toggleChecked(_ name: String) {
        if settings.checkedTagNames.contains(name) {
            settings.checkedTagNames.removeAll { $0 == name }
        } else {
            settings.checkedTagNames.append(name)
        }
    }

    private func loadTags() async {
        guard let client = settings.client else { return }
        tags = (try? await client.tags()) ?? []
    }
}
