import Foundation
import Observation

/// Lifetime counters of what this app has done, persisted across launches.
@MainActor
@Observable
final class StatsStore {
    private enum Keys {
        static let trashed = "statsTrashed"
        static let skipped = "statsSkipped"
        static let savedToAlbum = "statsSavedToAlbum"
        static let favorited = "statsFavorited"
    }

    private(set) var trashed: Int {
        didSet { UserDefaults.standard.set(trashed, forKey: Keys.trashed) }
    }
    private(set) var skipped: Int {
        didSet { UserDefaults.standard.set(skipped, forKey: Keys.skipped) }
    }
    private(set) var savedToAlbum: Int {
        didSet { UserDefaults.standard.set(savedToAlbum, forKey: Keys.savedToAlbum) }
    }
    private(set) var favorited: Int {
        didSet { UserDefaults.standard.set(favorited, forKey: Keys.favorited) }
    }

    init() {
        let defaults = UserDefaults.standard
        trashed = defaults.integer(forKey: Keys.trashed)
        skipped = defaults.integer(forKey: Keys.skipped)
        savedToAlbum = defaults.integer(forKey: Keys.savedToAlbum)
        favorited = defaults.integer(forKey: Keys.favorited)
    }

    /// Moves the lifetime totals by a session's change in `CullCounters`.
    ///
    /// Deliberately unclamped. The session's counters never go negative, so
    /// neither does the sum of their deltas; a clamp could only ever fire on a
    /// decrement whose matching increment then goes through in full, which is
    /// exactly how the old per-swipe bookkeeping drifted upward.
    func apply(_ delta: CullCounters) {
        guard !delta.isZero else { return }
        trashed += delta.trashed
        skipped += delta.skipped
        savedToAlbum += delta.savedToAlbum
        favorited += delta.favorited
    }

    /// For trashing outside a session (the browse grids); negative to roll back.
    func recordTrashed(count: Int) {
        apply(CullCounters(trashed: count))
    }
}
