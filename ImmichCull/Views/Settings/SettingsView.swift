import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var albums: [ImmichAlbum] = []
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
                    LabeledContent("Tag name") {
                        TextField("culled", text: $settings.checkedTagName)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                } header: {
                    Text("Already checked")
                } footer: {
                    Text("Kept photos are tagged with this name in Immich so they aren't offered again.")
                }

                Section {
                    Picker("Album", selection: $settings.destinationAlbumID) {
                        Text("None").tag("")
                        ForEach(albums) { album in
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
            .task { await loadAlbums() }
        }
    }

    private func loadAlbums() async {
        guard let client = settings.client else { return }
        albums = (try? await client.albums()) ?? []
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
