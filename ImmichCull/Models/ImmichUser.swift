import Foundation

struct ImmichUser: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let email: String
}
