import Foundation

enum ImmichError: LocalizedError {
    case invalidURL
    case badResponse
    case http(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            String(localized: "The server URL is not valid.")
        case .badResponse:
            String(localized: "The server sent an unexpected response.")
        case .http(let status, let message):
            if let message, !message.isEmpty {
                String(localized: "Server error \(status): \(message)")
            } else {
                String(localized: "Server error \(status).")
            }
        }
    }
}
