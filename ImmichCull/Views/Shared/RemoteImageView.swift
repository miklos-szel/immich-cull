import SwiftUI

/// Loads an authenticated Immich image and shows a placeholder while in flight.
struct RemoteImageView: View {
    let url: URL
    let apiKey: String
    var contentMode: ContentMode = .fit

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
        .task(id: url) {
            didFail = false
            do {
                image = try await ImageLoader.shared.image(at: url, apiKey: apiKey)
            } catch {
                didFail = true
            }
        }
    }
}
