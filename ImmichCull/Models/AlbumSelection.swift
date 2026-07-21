import Foundation

enum AlbumSelection: Identifiable, Hashable, Sendable {
    case entireLibrary
    case albums([ImmichAlbum])
    /// Assets that belong to no album — the "unsorted" pile.
    case notInAnyAlbum

    var id: String {
        switch self {
        case .entireLibrary:
            "entire-library"
        case .albums(let albums):
            albums.map(\.id).joined(separator: ",")
        case .notInAnyAlbum:
            "not-in-any-album"
        }
    }

    /// Album IDs to pass to the search endpoint; nil means no album filter.
    var albumIDs: [String]? {
        switch self {
        case .entireLibrary, .notInAnyAlbum:
            nil
        case .albums(let albums):
            albums.map(\.id)
        }
    }

    /// `true` when the run should fetch only assets in no album.
    var isNotInAlbum: Bool {
        if case .notInAnyAlbum = self { return true }
        return false
    }

    var title: String {
        switch self {
        case .entireLibrary:
            String(localized: "Entire library")
        case .albums(let albums):
            albums.map(\.albumName).joined(separator: ", ")
        case .notInAnyAlbum:
            String(localized: "Not in any album")
        }
    }
}
