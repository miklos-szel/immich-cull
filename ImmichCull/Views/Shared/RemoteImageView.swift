import SwiftUI

/// Loads an authenticated Immich image and shows a placeholder while in flight.
///
/// Immich serves no preview for some assets, so when `fallbackURL` is set (the
/// original file) it is tried before giving up. `onUnavailable` fires when
/// neither could be loaded — the caller decides whether that means the asset is
/// actually gone.
struct RemoteImageView: View {
    let url: URL
    let apiKey: String
    var contentMode: ContentMode = .fit
    var fallbackURL: URL?
    var onUnavailable: (() -> Void)?

    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        if didFail {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Failed to load image")
                        } else {
                            ProgressView()
                        }
                    }
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        didFail = false
        image = nil

        if let loaded = try? await ImageLoader.shared.image(at: url, apiKey: apiKey) {
            image = loaded
            return
        }
        // Immich serves no preview for some assets (404) and answers 400 for
        // ones that are gone, so try the original before giving up.
        if let fallbackURL,
           let loaded = try? await ImageLoader.shared.image(at: fallbackURL, apiKey: apiKey) {
            image = loaded
            return
        }
        didFail = true
        onUnavailable?()
    }
}
