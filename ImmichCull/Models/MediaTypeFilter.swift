import Foundation

/// Which kinds of asset a culling run offers. Both on by default — the filter
/// exists to review one kind at a time, not to hide anything permanently.
enum MediaTypeFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case photosOnly
    case videosOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: String(localized: "Photos & Videos")
        case .photosOnly: String(localized: "Photos Only")
        case .videosOnly: String(localized: "Videos Only")
        }
    }

    /// The Immich search API's `type` value; `nil` means don't filter.
    var searchType: String? {
        switch self {
        case .all: nil
        case .photosOnly: "IMAGE"
        case .videosOnly: "VIDEO"
        }
    }

    /// Builds the filter from two independent toggles. Turning both off would
    /// leave nothing to cull, so that falls back to showing everything.
    static func from(includePhotos: Bool, includeVideos: Bool) -> MediaTypeFilter {
        switch (includePhotos, includeVideos) {
        case (true, false): .photosOnly
        case (false, true): .videosOnly
        default: .all
        }
    }
}
