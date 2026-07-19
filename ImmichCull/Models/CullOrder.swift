import Foundation

enum CullOrder: String, CaseIterable, Identifiable, Sendable {
    case newestFirst
    case oldestFirst

    var id: String { rawValue }

    var apiValue: String {
        switch self {
        case .newestFirst: "desc"
        case .oldestFirst: "asc"
        }
    }

    var label: String {
        switch self {
        case .newestFirst: String(localized: "Newest first")
        case .oldestFirst: String(localized: "Oldest first")
        }
    }
}
