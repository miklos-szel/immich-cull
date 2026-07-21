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

        if let loaded = await fetch(url, retries: 2) {
            image = loaded
            return
        }
        // A cancelled fetch returns nil just like a 404 does; don't let it fall
        // through to the fallback or fire onUnavailable, which could make the
        // caller drop an asset that's actually fine.
        if Task.isCancelled { return }
        // Immich serves no preview for some assets (404) and answers 400 for
        // ones that are gone, so try the original before giving up.
        if let fallbackURL, let loaded = await fetch(fallbackURL, retries: 1) {
            image = loaded
            return
        }
        if Task.isCancelled { return }
        didFail = true
        onUnavailable?()
    }

    /// Retries transient failures (timeouts, dropped connections) with a short
    /// backoff — a full grid firing dozens of requests at once against a real
    /// server drops some, and without a retry those cells stay broken forever.
    /// A genuine 404 is not retried: the preview simply isn't there.
    private func fetch(_ url: URL, retries: Int) async -> UIImage? {
        var attempt = 0
        while true {
            do {
                return try await ImageLoader.shared.image(at: url, apiKey: apiKey)
            } catch ImmichError.notFound {
                return nil
            } catch {
                guard attempt < retries, !Task.isCancelled else { return nil }
                attempt += 1
                try? await Task.sleep(for: .milliseconds(300 * attempt))
            }
        }
    }
}
