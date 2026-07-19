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

    func record(_ kind: CullActionKind) {
        adjust(kind, by: 1)
    }

    func revert(_ kind: CullActionKind) {
        adjust(kind, by: -1)
    }

    func recordTrashed(count: Int) {
        trashed += count
    }

    private func adjust(_ kind: CullActionKind, by delta: Int) {
        switch kind {
        case .trash: trashed = max(0, trashed + delta)
        case .skip: skipped = max(0, skipped + delta)
        case .saveToAlbum: savedToAlbum = max(0, savedToAlbum + delta)
        case .favorite: favorited = max(0, favorited + delta)
        }
    }
}
