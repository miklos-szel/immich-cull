import Foundation

enum AssetType: String, Codable, Sendable {
    case image = "IMAGE"
    case video = "VIDEO"
    case audio = "AUDIO"
    case other = "OTHER"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AssetType(rawValue: raw) ?? .other
    }
}
