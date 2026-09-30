import SwiftUI

/// Loads an authenticated Immich image and shows a placeholder while in flight.
///
/// Mirrors the iOS `RemoteImageView` invariants: a cancelled fetch (scroll or
/// dismissal) returns nil exactly like a 404, so the `Task.isCancelled` guards
/// keep it from falling through to the fallback or firing `onUnavailable` — a
/// cancelled load must not make a caller drop a healthy asset.
struct RemoteImageMacView: View {
    let url: URL
    let apiKey: String
    var contentMode: ContentMode = .fit
    var fallbackURL: URL?
    var onUnavailable: (() -> Void)?

    @State private var image: PlatformImage?
    @State private var didFail = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
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
                                .controlSize(.small)
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
        if Task.isCancelled { return }
        if let fallbackURL, let loaded = await fetch(fallbackURL, retries: 1) {
            image = loaded
            return
        }
        if Task.isCancelled { return }
        didFail = true
        onUnavailable?()
    }

    private func fetch(_ url: URL, retries: Int) async -> PlatformImage? {
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
