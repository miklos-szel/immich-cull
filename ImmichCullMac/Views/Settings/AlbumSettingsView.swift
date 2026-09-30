import SwiftUI

struct AlbumSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var albums: [ImmichAlbum] = []

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Album", selection: $settings.destinationAlbumID) {
                    Text("None").tag("")
                    ForEach(albums) { album in
                        Text(album.albumName).tag(album.id)
                    }
                }
                .onChange(of: settings.destinationAlbumID) { _, id in
                    settings.destinationAlbumName = albums.first { $0.id == id }?.albumName ?? ""
                }
            } header: {
                Text("Pull-down album")
            } footer: {
                Text("The “Add to Album” action puts a photo into this album.")
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { await loadAlbums() }
    }

    private func loadAlbums() async {
        guard let client = settings.client else { return }
        albums = (try? await client.albums()) ?? []
    }
}
