import SwiftUI
import AVKit

/// Plays an Immich video, sending the `x-api-key` header AVPlayer needs (the
/// plain URL form can't carry it).
///
/// Wraps AppKit's `AVPlayerView` via `NSViewRepresentable` rather than SwiftUI's
/// `VideoPlayer`: the latter (`_AVKit_SwiftUI`) crashes on class-metadata
/// instantiation on macOS. This is the same reason the iOS app bridges to a
/// player layer instead of using `VideoPlayer`.
struct VideoCardMacView: NSViewRepresentable {
    let url: URL
    let apiKey: String

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        context.coordinator.load(url: url, apiKey: apiKey, into: view)
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // Swap the item when the deck advances to a different video.
        if context.coordinator.url != url {
            context.coordinator.load(url: url, apiKey: apiKey, into: nsView)
        }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        nsView.player?.pause()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private(set) var url: URL?

        func load(url: URL, apiKey: String, into view: AVPlayerView) {
            self.url = url
            let asset = AVURLAsset(url: url, options: [
                "AVURLAssetHTTPHeaderFieldsKey": ["x-api-key": apiKey]
            ])
            let item = AVPlayerItem(asset: asset)
            if let player = view.player {
                player.replaceCurrentItem(with: item)
            } else {
                view.player = AVPlayer(playerItem: item)
            }
        }
    }
}
