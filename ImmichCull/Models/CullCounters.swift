import Foundation

/// The per-kind tallies a culling session shows, and the unit the lifetime
/// stats are adjusted by.
///
/// A session *derives* these from its state rather than incrementing them per
/// swipe (see `CullSession.counters`), and the lifetime stats move by the
/// difference before and after each mutation. Incrementing in each code path
/// drifted: clamped decrements that undo then re-incremented, and a back-step
/// followed by the same swipe counting one photo twice.
struct CullCounters: Equatable, Sendable {
    var trashed = 0
    var skipped = 0
    var savedToAlbum = 0
    var favorited = 0

    static func - (lhs: CullCounters, rhs: CullCounters) -> CullCounters {
        CullCounters(trashed: lhs.trashed - rhs.trashed,
                     skipped: lhs.skipped - rhs.skipped,
                     savedToAlbum: lhs.savedToAlbum - rhs.savedToAlbum,
                     favorited: lhs.favorited - rhs.favorited)
    }

    var isZero: Bool { self == CullCounters() }
}
