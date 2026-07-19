import Foundation

struct DiscoveredServer: Identifiable, Hashable, Sendable {
    let url: URL

    var id: String { url.absoluteString }
}
