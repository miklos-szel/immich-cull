import Foundation

enum AlbumSelection: Identifiable, Hashable, Sendable {
    case entireLibrary
    case albums([ImmichAlbum])

    var id: String {
        switch self {
        case .entireLibrary:
            "entire-library"
        case .albums(let albums):
            albums.map(\.id).joined(separator: ",")
        }
    }

    /// Album IDs to pass to the search endpoint; nil means no album filter.
    var albumIDs: [String]? {
        switch self {
        case .entireLibrary:
            nil
        case .albums(let albums):
            albums.map(\.id)
        }
    }

    var title: String {
        switch self {
        case .entireLibrary:
            String(localized: "Entire library")
        case .albums(let albums):
            albums.map(\.albumName).joined(separator: ", ")
        }
    }
}
