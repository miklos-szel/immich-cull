import Foundation
import Observation

/// Downloads thumbnails for the library's images and scores their sharpness.
@MainActor
@Observable
final class BlurScanSession {
    enum Phase: Equatable {
        case scanning
        case finished
        case failed(String)
    }

    /// Scores below this are considered likely blurry and preselected.
    static let blurryThreshold = 90.0
    private static let assetLimit = 1500
    private static let concurrency = 6

    private let client: ImmichClient

    private(set) var phase: Phase = .scanning
    private(set) var totalCount = 0
    private(set) var scannedCount = 0
    private(set) var results: [BlurResult] = []

    init(client: ImmichClient) {
        self.client = client
    }

    func start() async {
        do {
            let images = try await client
                .fetchAssets(albumIDs: nil, tagIDs: nil, order: "desc", limit: Self.assetLimit)
                .filter { $0.type == .image }
            totalCount = images.count
            let client = client
            await withTaskGroup(of: BlurResult?.self) { group in
                var iterator = images.makeIterator()
                for _ in 0..<Self.concurrency {
                    guard let asset = iterator.next() else { break }
                    group.addTask { await Self.score(asset, client: client) }
                }
                for await result in group {
                    scannedCount += 1
                    if let result {
                        results.append(result)
                    }
                    if let asset = iterator.next() {
                        group.addTask { await Self.score(asset, client: client) }
                    }
                }
            }
            results.sort { $0.score < $1.score }
            phase = .finished
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func removeResults(withIDs ids: Set<String>) {
        results.removeAll { ids.contains($0.id) }
    }

    private nonisolated static func score(_ asset: ImmichAsset, client: ImmichClient) async -> BlurResult? {
        let url = client.thumbnailURL(assetID: asset.id, size: "thumbnail")
        guard let image = try? await ImageLoader.shared.image(at: url, apiKey: client.apiKey) else {
            return nil
        }
        return BlurResult(asset: asset, score: BlurAnalyzer.sharpnessScore(of: image))
    }
}
