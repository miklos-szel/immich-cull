import SwiftUI
import AVKit

/// Muted, looping playback of an Immich video asset.
struct VideoCardView: View {
    let url: URL
    let apiKey: String

    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    .allowsHitTesting(false) // Let the card's drag gesture win.
            } else {
                ProgressView()
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
