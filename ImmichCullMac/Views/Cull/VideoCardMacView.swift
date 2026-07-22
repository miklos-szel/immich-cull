import SwiftUI
import AVKit

/// Plays an Immich video, sending the `x-api-key` header AVPlayer needs (the
/// plain URL form can't carry it).
struct VideoCardMacView: View {
    let url: URL
    let apiKey: String

    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .onDisappear { player.pause() }
            } else {
                ProgressView()
            }
        }
        .task(id: url) {
            let asset = AVURLAsset(url: url, options: [
                "AVURLAssetHTTPHeaderFieldsKey": ["x-api-key": apiKey]
            ])
            let item = AVPlayerItem(asset: asset)
            player = AVPlayer(playerItem: item)
        }
    }
}
