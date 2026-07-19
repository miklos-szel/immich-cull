import SwiftUI

struct AlbumRowView: View {
    let album: ImmichAlbum
    let isSelected: Bool
    let thumbnailURL: URL?
    let apiKey: String
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
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
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .imageScale(.large)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
