import Foundation

struct ImmichTag: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let value: String
}
