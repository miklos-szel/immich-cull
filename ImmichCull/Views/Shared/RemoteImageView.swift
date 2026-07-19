import SwiftUI

/// Loads an authenticated Immich image and shows a placeholder while in flight.
///
/// Immich 404s previews it hasn't generated yet, so when `fallbackURL` is set
/// (the original file) it is tried before giving up. `onUnavailable` fires only
/// when nothing could be loaded because the server has no such asset.
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
        do {
            image = try await ImageLoader.shared.image(at: url, apiKey: apiKey)
        } catch ImmichError.notFound {
            await loadFallback(missing: true)
        } catch {
            await loadFallback(missing: false)
        }
    }

    /// Tries the original file; `missing` means the preview itself was a 404.
    private func loadFallback(missing: Bool) async {
        guard let fallbackURL else {
            didFail = true
            if missing { onUnavailable?() }
            return
        }
        do {
            image = try await ImageLoader.shared.image(at: fallbackURL, apiKey: apiKey)
        } catch ImmichError.notFound {
            didFail = true
            onUnavailable?()
        } catch {
            didFail = true
        }
    }
}
