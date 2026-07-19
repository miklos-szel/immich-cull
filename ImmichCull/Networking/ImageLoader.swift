import UIKit

/// Fetches authenticated Immich images with memory + disk caching.
final class ImageLoader: Sendable {
    static let shared = ImageLoader()

    private let session: URLSession

    private init() {
        // Memory-only: these are the user's private photos fetched with an API
        // key, so nothing is persisted to disk where it would outlive a sign-out.
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = URLCache(memoryCapacity: 128 * 1024 * 1024, diskCapacity: 0)
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
    }

    /// Drops every cached image; call when the server or account changes.
    func clearCache() {
        session.configuration.urlCache?.removeAllCachedResponses()
    }

    func image(at url: URL, apiKey: String) async throws -> UIImage {
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ImmichError.badResponse }
        // Immich 404s previews it hasn't generated (and assets that are gone),
        // which callers handle by falling back to the original.
        guard http.statusCode != 404 else { throw ImmichError.notFound }
        guard (200..<300).contains(http.statusCode), let image = UIImage(data: data) else {
            throw ImmichError.badResponse
        }
        return image.preparingForDisplay() ?? image
    }

    /// Fire-and-forget warm-up of the cache for upcoming cards.
    func prefetch(url: URL, apiKey: String) {
        Task {
            _ = try? await image(at: url, apiKey: apiKey)
        }
    }
}
