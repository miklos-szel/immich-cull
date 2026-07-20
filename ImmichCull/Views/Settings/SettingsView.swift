import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var albums: [ImmichAlbum] = []
    @State private var tagNames: [String] = []
    @State private var isShowingSignOutConfirm = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $settings.swipeUpAction) {
                        SwipeActionOptionsView()
                    } label: {
                        Label("Up", systemImage: "arrow.up")
                    }
                    Picker(selection: $settings.swipeDownAction) {
                        SwipeActionOptionsView()
                    } label: {
                        Label("Down", systemImage: "arrow.down")
                    }
                    Picker(selection: $settings.swipeLeftAction) {
                        SwipeActionOptionsView()
                    } label: {
                        Label("Left", systemImage: "arrow.left")
                    }
                    Picker(selection: $settings.swipeRightAction) {
                        SwipeActionOptionsView()
                    } label: {
                        Label("Right", systemImage: "arrow.right")
                    }
                } header: {
                    Text("Swipe gestures")
                } footer: {
                    Text("Choose what each swipe direction does while culling.")
                }

                Section {
                    Picker("Order", selection: $settings.order) {
                        ForEach(CullOrder.allCases) { order in
                            Text(order.label).tag(order)
                        }
                    }
                } header: {
                    Text("Review order")
                }

                Section {
                    Toggle("Photos", isOn: $settings.includePhotos)
                    Toggle("Videos", isOn: $settings.includeVideos)
                } header: {
                    Text("What to include")
                } footer: {
                    if !settings.includePhotos && !settings.includeVideos {
                        Text("With both off there'd be nothing to review, so everything is offered.")
                    } else {
                        Text("Applies to the next culling run.")
                    }
                }

                Section {
                    Picker("Appearance", selection: $settings.appearance) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Appearance")
                }

                Section {
                    Toggle("Show file name and date", isOn: $settings.showCardInfo)
                    Toggle("Also delete from iPhone Photos", isOn: $settings.alsoDeleteFromPhotos)
                } header: {
                    Text("Culling")
                } footer: {
                    Text("When enabled, trashing a photo also removes the matching item from this iPhone's photo library (if present). iOS will ask you to confirm.")
                }

                Section {
                    Toggle("Offer checked photos again", isOn: $settings.reOfferChecked)
                    NavigationLink {
                        TagSelectionView()
                    } label: {
                        LabeledContent("Tags", value: checkedTagsSummary)
                    }
                    .accessibilityIdentifier("checkedTagsLink")
                    Picker("Mark culled with", selection: $settings.markTagName) {
                        // The chosen tag need not exist yet — it is created on
                        // demand when the first asset is marked.
                        ForEach(markTagOptions, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .accessibilityIdentifier("markTagPicker")
                } header: {
                    Text("Already culled")
                } footer: {
                    Text("Photos carrying any of these tags aren't offered again. Culled photos are tagged with the one you mark with.")
                }

                Section {
                    Picker("Album", selection: $settings.destinationAlbumID) {
                        Text("None").tag("")
                        ForEach(sortedAlbums) { album in
                            Text(album.albumName).tag(album.id)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .accessibilityIdentifier("destinationAlbumPicker")
                } header: {
                    Text("Pull-down album")
                } footer: {
                    Text("Pulling a photo down adds it to this album.")
                }

                StatsSectionView()

                Section {
                    LabeledContent("Server", value: settings.serverURLString)
                    Button("Sign Out", role: .destructive, action: confirmSignOut)
                        .confirmationDialog(
                            "Sign out and forget this server?",
                            isPresented: $isShowingSignOutConfirm,
                            titleVisibility: .visible
                        ) {
                            Button("Sign Out", role: .destructive, action: signOut)
                        }
                } header: {
                    Text("Server")
                }

                Section {
                } footer: {
                    Text("immich-cull is an unofficial, independent app and is not affiliated with, endorsed by, or sponsored by the Immich project or its maintainers.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: close)
                }
            }
            .onChange(of: settings.destinationAlbumID) {
                settings.destinationAlbumName = albums.first { $0.id == settings.destinationAlbumID }?.albumName ?? ""
            }
            .task {
                await loadAlbums()
                await loadTags()
            }
        }
    }

    private var checkedTagsSummary: String {
        switch settings.checkedTagNames.count {
        case 0: String(localized: "None")
        case 1: settings.checkedTagNames[0]
        default: String(localized: "\(settings.checkedTagNames.count) selected")
        }
    }

    /// The write tag is offered from the same list you excluded by, plus
    /// whatever is currently set — otherwise picking a tag the server hasn't
    /// heard of yet would silently reset the selection.
    private var markTagOptions: [String] {
        var options = tagNames
        if !options.contains(settings.markTagName) {
            options.insert(settings.markTagName, at: 0)
        }
        return options
    }

    /// Sorted at render rather than at load, because the "Review order" picker
    /// sits in this same screen — the album list has to reorder as you change it.
    private var sortedAlbums: [ImmichAlbum] {
        albums.sorted(by: settings.order)
    }

    private func loadAlbums() async {
        guard let client = settings.client else { return }
        albums = (try? await client.albums()) ?? []
    }

    private func loadTags() async {
        guard let client = settings.client else { return }
        let tags = (try? await client.tags()) ?? []
        tagNames = tags.map(\.name).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private func confirmSignOut() {
        isShowingSignOutConfirm = true
    }

    private func signOut() {
        settings.signOut()
        dismiss()
    }

    private func close() {
        dismiss()
    }
}

#Preview {
    SettingsView()
        .environment(SettingsStore())
}
