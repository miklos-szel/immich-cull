import SwiftUI
import AVKit

/// Owns the deck's single `AVPlayer` so the deck's keyboard handler can toggle
/// playback (Space) without reaching into the view. Kept across cards; the URL
/// is swapped as the deck advances.
@MainActor
final class VideoPlaybackController {
    let player = AVPlayer()
    private var currentURL: URL?

    func load(url: URL, apiKey: String) {
        guard currentURL != url else { return }
        currentURL = url
        player.pause()
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": ["x-api-key": apiKey]
        ])
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
    }

    /// Space toggles play/pause.
    func toggle() {
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
    }

    func pause() { player.pause() }
}

/// Plays an Immich video, sending the `x-api-key` header AVPlayer needs (the
/// plain URL form can't carry it).
///
/// Wraps AppKit's `AVPlayerView` via `NSViewRepresentable` rather than SwiftUI's
/// `VideoPlayer`: the latter (`_AVKit_SwiftUI`) crashes on class-metadata
/// instantiation on macOS. This is the same reason the iOS app bridges to a
/// player layer instead of using `VideoPlayer`.
struct VideoCardMacView: NSViewRepresentable {
    let controller: VideoPlaybackController
    let url: URL
    let apiKey: String

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.player = controller.player
        controller.load(url: url, apiKey: apiKey)
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== controller.player { nsView.player = controller.player }
        controller.load(url: url, apiKey: apiKey)
    }
}
