import SwiftUI
import AVFoundation

/// Muted, looping playback of an Immich video asset. Rendered through
/// `PlayerLayerView` rather than `VideoPlayer` so the letterbox bars take the
/// card's background colour instead of black — see that file for why.
struct VideoCardView: View {
    let url: URL
    let apiKey: String

    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        // No placeholder: the card underneath already shows the poster still, and
        // the player layer is transparent until it has frames, so there's nothing
        // to flash between them.
        ZStack {
            if let player {
                PlayerLayerView(player: player)
                    .allowsHitTesting(false) // Let the card's drag gesture win.
            }
        }
        .task { setUpPlayer() }
        .onDisappear(perform: tearDown)
    }

    private func setUpPlayer() {
        guard player == nil else { return }
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": ["x-api-key": apiKey]
        ])
        let item = AVPlayerItem(asset: asset)
        let queuePlayer = AVQueuePlayer()
        looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        queuePlayer.isMuted = true
        queuePlayer.play()
        player = queuePlayer
    }

    private func tearDown() {
        player?.pause()
        looper = nil
        player = nil
    }
}
