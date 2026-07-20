import Foundation

extension Array where Element == ImmichAlbum {
    /// Orders albums the same way the culling run orders photos, so "newest
    /// first" means the same thing on the album list as it does in the deck.
    ///
    /// Albums with no date sort last in *both* directions rather than being
    /// treated as infinitely old or infinitely new — an undated album is
    /// usually an empty one, and it has no business leading the list.
    func sorted(by order: CullOrder) -> [ImmichAlbum] {
        sorted { left, right in
            switch (left.sortDate, right.sortDate) {
            case let (leftDate?, rightDate?):
                if leftDate == rightDate {
                    return left.albumName.localizedStandardCompare(right.albumName) == .orderedAscending
                }
                return order == .newestFirst ? leftDate > rightDate : leftDate < rightDate
            case (nil, nil):
                return left.albumName.localizedStandardCompare(right.albumName) == .orderedAscending
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            }
        }
    }
}
