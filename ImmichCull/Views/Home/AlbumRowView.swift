import SwiftUI

struct AlbumRowView: View {
    let album: ImmichAlbum
    let thumbnailURL: URL?
    let apiKey: String
    /// Tapping an album opens its full-screen stream rather than selecting it.
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                thumbnail
                VStack(alignment: .leading) {
                    Text(album.albumName)
                        .foregroundStyle(.primary)
                    Text("^[\(album.assetCount) item](inflect: true)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
        }
    }

    private var thumbnail: some View {
        ZStack {
            if let thumbnailURL {
                RemoteImageView(url: thumbnailURL, apiKey: apiKey, contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo.on.rectangle")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(.rect(cornerRadius: 8))
        .accessibilityHidden(true)
    }
}
