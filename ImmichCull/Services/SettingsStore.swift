import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    private enum Keys {
        static let serverURL = "serverURL"
        static let order = "cullOrder"
        static let destinationAlbumID = "destinationAlbumID"
        static let destinationAlbumName = "destinationAlbumName"
        static let reOfferChecked = "reOfferChecked"
        /// Superseded by `checkedTagNames` + `markTagName`; still read once by
        /// the migration in `init`.
        static let legacyCheckedTagName = "checkedTagName"
        static let checkedTagNames = "checkedTagNames"
        static let markTagName = "markTagName"
        static let didMigrateTags = "didMigrateTags"
        static let appearance = "appearance"
        static let showCardInfo = "showCardInfo"
        static let alsoDeleteFromPhotos = "alsoDeleteFromPhotos"
        static let includePhotos = "includePhotos"
        static let includeVideos = "includeVideos"
        static let apiKey = "apiKey"
        static let swipeUp = "swipeUpAction"
        static let swipeDown = "swipeDownAction"
        static let swipeLeft = "swipeLeftAction"
        static let swipeRight = "swipeRightAction"
    }

    var serverURLString: String {
        didSet { UserDefaults.standard.set(serverURLString, forKey: Keys.serverURL) }
    }
    var apiKey: String {
        didSet { KeychainStore.set(apiKey, for: Keys.apiKey) }
    }
    var order: CullOrder {
        didSet { UserDefaults.standard.set(order.rawValue, forKey: Keys.order) }
    }
    var destinationAlbumID: String {
        didSet { UserDefaults.standard.set(destinationAlbumID, forKey: Keys.destinationAlbumID) }
    }
    var destinationAlbumName: String {
        didSet { UserDefaults.standard.set(destinationAlbumName, forKey: Keys.destinationAlbumName) }
    }
    /// When true, assets already marked checked are offered again.
    var reOfferChecked: Bool {
        didSet { UserDefaults.standard.set(reOfferChecked, forKey: Keys.reOfferChecked) }
    }
    /// Tags that mean "already culled". An asset carrying any of them is
    /// treated as reviewed and left out of the run unless `reOfferChecked`.
    var checkedTagNames: [String] {
        didSet { UserDefaults.standard.set(checkedTagNames, forKey: Keys.checkedTagNames) }
    }
    /// The one tag actually written when an asset is marked reviewed. Separate
    /// from `checkedTagNames` because reading many tags and writing one are
    /// different jobs — you may want to honour a tag you never apply yourself.
    var markTagName: String {
        didSet { UserDefaults.standard.set(markTagName, forKey: Keys.markTagName) }
    }
    var appearance: AppTheme {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Keys.appearance) }
    }
    /// Whether the filename and capture date are shown under the current card.
    var showCardInfo: Bool {
        didSet { UserDefaults.standard.set(showCardInfo, forKey: Keys.showCardInfo) }
    }
    /// Also remove the matching photo/video from the local iPhone library when trashing.
    var alsoDeleteFromPhotos: Bool {
        didSet { UserDefaults.standard.set(alsoDeleteFromPhotos, forKey: Keys.alsoDeleteFromPhotos) }
    }
    /// Which asset kinds a culling run offers. Both default to on; turning both
    /// off would leave nothing to cull, so `mediaFilter` falls back to all.
    var includePhotos: Bool {
        didSet { UserDefaults.standard.set(includePhotos, forKey: Keys.includePhotos) }
    }
    var includeVideos: Bool {
        didSet { UserDefaults.standard.set(includeVideos, forKey: Keys.includeVideos) }
    }

    var mediaFilter: MediaTypeFilter {
        .from(includePhotos: includePhotos, includeVideos: includeVideos)
    }

    var swipeUpAction: SwipeAction {
        didSet { UserDefaults.standard.set(swipeUpAction.rawValue, forKey: Keys.swipeUp) }
    }
    var swipeDownAction: SwipeAction {
        didSet { UserDefaults.standard.set(swipeDownAction.rawValue, forKey: Keys.swipeDown) }
    }
    var swipeLeftAction: SwipeAction {
        didSet { UserDefaults.standard.set(swipeLeftAction.rawValue, forKey: Keys.swipeLeft) }
    }
    var swipeRightAction: SwipeAction {
        didSet { UserDefaults.standard.set(swipeRightAction.rawValue, forKey: Keys.swipeRight) }
    }

    func action(for direction: SwipeDirection) -> SwipeAction {
        switch direction {
        case .up: swipeUpAction
        case .down: swipeDownAction
        case .left: swipeLeftAction
        case .right: swipeRightAction
        }
    }

    init() {
        // Defaults for toggles that should start enabled.
        UserDefaults.standard.register(defaults: [
            Keys.alsoDeleteFromPhotos: true,
            Keys.includePhotos: true,
            Keys.includeVideos: true,
        ])

        // UI tests pass this flag to start from a clean slate.
        if CommandLine.arguments.contains("--uitest-reset") {
            if let bundleID = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
            }
            KeychainStore.delete(Keys.apiKey)
        }
        let defaults = UserDefaults.standard
        serverURLString = defaults.string(forKey: Keys.serverURL) ?? ""
        apiKey = KeychainStore.string(for: Keys.apiKey) ?? ""
        order = CullOrder(rawValue: defaults.string(forKey: Keys.order) ?? "") ?? .newestFirst
        destinationAlbumID = defaults.string(forKey: Keys.destinationAlbumID) ?? ""
        destinationAlbumName = defaults.string(forKey: Keys.destinationAlbumName) ?? ""
        reOfferChecked = defaults.bool(forKey: Keys.reOfferChecked)
        (checkedTagNames, markTagName) = Self.loadTagSettings(from: defaults)
        // Defaults to .system, i.e. follow the device appearance.
        appearance = AppTheme(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        showCardInfo = defaults.bool(forKey: Keys.showCardInfo) // Defaults to false (hidden).
        alsoDeleteFromPhotos = defaults.bool(forKey: Keys.alsoDeleteFromPhotos)
        includePhotos = defaults.bool(forKey: Keys.includePhotos)
        includeVideos = defaults.bool(forKey: Keys.includeVideos)
        swipeUpAction = SwipeAction(rawValue: defaults.string(forKey: Keys.swipeUp) ?? "") ?? .trash
        swipeDownAction = SwipeAction(rawValue: defaults.string(forKey: Keys.swipeDown) ?? "") ?? .saveToAlbum
        swipeLeftAction = SwipeAction(rawValue: defaults.string(forKey: Keys.swipeLeft) ?? "") ?? .nextImage
        swipeRightAction = SwipeAction(rawValue: defaults.string(forKey: Keys.swipeRight) ?? "") ?? .previousImage

        // UI tests can preconfigure the pull-down destination album, since
        // XCUITest cannot reliably tap iOS 26 toolbar buttons to reach Settings.
        let environment = ProcessInfo.processInfo.environment
        if let albumID = environment["UITEST_ALBUM_ID"] {
            destinationAlbumID = albumID
            destinationAlbumName = environment["UITEST_ALBUM_NAME"] ?? "Album"
        }
        // Same reasoning for the tag settings, which are two screens deep.
        if let tags = environment["UITEST_CHECKED_TAGS"] {
            checkedTagNames = tags.split(separator: ",").map(String.init)
            markTagName = checkedTagNames.first ?? markTagName
        }
        // Direct connection injection for automated/visual test runs.
        if let url = environment["UITEST_SERVER_URL"] {
            serverURLString = url
        }
        if let key = environment["UITEST_API_KEY"] {
            apiKey = key
        }
        // Keep the photo-library permission prompt out of automated runs.
        if environment["UITEST_DISABLE_PHOTO_DELETE"] != nil {
            alsoDeleteFromPhotos = false
        }
    }

    /// Reads the tag settings, migrating the single `checkedTagName` this app
    /// used to store into the exclusion list plus the write tag.
    ///
    /// The write is explicit rather than relying on the `didSet` accessors:
    /// `didSet` does not fire for the first assignment to a property inside
    /// `init`, which is what lets the other settings load without rewriting
    /// themselves. A migration written that way would silently re-derive from
    /// the legacy key on every launch instead of completing once, so a later
    /// edit to the list could be undone by the next launch.
    private static func loadTagSettings(from defaults: UserDefaults) -> (names: [String], mark: String) {
        let fallback = "culled"

        if !defaults.bool(forKey: Keys.didMigrateTags) {
            let legacy = defaults.string(forKey: Keys.legacyCheckedTagName) ?? ""
            let name = legacy.isEmpty ? fallback : legacy
            defaults.set([name], forKey: Keys.checkedTagNames)
            defaults.set(name, forKey: Keys.markTagName)
            defaults.set(true, forKey: Keys.didMigrateTags)
            return ([name], name)
        }

        let stored = defaults.stringArray(forKey: Keys.checkedTagNames) ?? []
        let mark = defaults.string(forKey: Keys.markTagName) ?? ""
        return (stored, mark.isEmpty ? fallback : mark)
    }

    var serverURL: URL? {
        let trimmed = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        guard let url = URL(string: normalized), url.scheme != nil, url.host() != nil else { return nil }
        return url
    }

    var isConfigured: Bool {
        serverURL != nil && !apiKey.isEmpty
    }

    var client: ImmichClient? {
        guard let serverURL, !apiKey.isEmpty else { return nil }
        return ImmichClient(serverURL: serverURL, apiKey: apiKey)
    }

    func signOut() {
        serverURLString = ""
        apiKey = ""
        destinationAlbumID = ""
        destinationAlbumName = ""
        // Don't leave the previous account's photos in the image cache.
        ImageLoader.shared.clearCache()
    }
}
