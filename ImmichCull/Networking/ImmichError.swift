import Foundation

enum ImmichError: LocalizedError {
    case invalidURL
    case badResponse
    /// The server has no such resource — e.g. a preview Immich never generated,
    /// or an asset removed since the queue was built.
    case notFound
    case http(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            String(localized: "The server URL is not valid.")
        case .badResponse:
            String(localized: "The server sent an unexpected response.")
        case .notFound:
            String(localized: "That item is no longer on the server.")
        case .http(let status, let message):
            if let message, !message.isEmpty {
                String(localized: "Server error \(status): \(message)")
            } else {
                String(localized: "Server error \(status).")
            }
        }
    }
}
