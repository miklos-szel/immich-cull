import SwiftUI
import AVFoundation

/// Bridges to UIKit for the same reason `ScrollPanDisabler` does: the behaviour
/// has no SwiftUI equivalent. `VideoPlayer` draws an opaque black backing of its
/// own, so a portrait video sat in black bars while a portrait photo sat on the
/// card's `.background(.background)` — the two looked like different apps in
/// light mode. An `AVPlayerLayer` with a clear background lets the card's own
/// colour show through the letterbox.
///
/// Losing `VideoPlayer`'s transport controls costs nothing: the card sets
/// `allowsHitTesting(false)` so the drag gesture wins, and they were never
/// reachable.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        view.backgroundColor = .clear
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.backgroundColor = UIColor.clear.cgColor
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerHostView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }

    /// Backing the view with `AVPlayerLayer` directly means the layer resizes
    /// with the view for free — setting a sublayer's frame by hand lags a
    /// rotation by a frame.
    final class PlayerHostView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
