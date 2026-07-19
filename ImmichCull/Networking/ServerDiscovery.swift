import Foundation
import Observation

@MainActor
@Observable
final class ServerDiscovery {
    private(set) var servers: [DiscoveredServer] = []
    private(set) var isScanning = false

    private static let immichPort = 2283
    private static let probeConcurrency = 32

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        servers = []

        let hosts = LocalNetwork.subnetHosts()
        guard !hosts.isEmpty else { return }

        await withTaskGroup(of: DiscoveredServer?.self) { group in
            var iterator = hosts.makeIterator()
            for _ in 0..<Self.probeConcurrency {
                guard let host = iterator.next() else { break }
                group.addTask { await Self.probe(host: host) }
            }
            for await found in group {
                if let found {
                    servers.append(found)
                }
                if let host = iterator.next() {
                    group.addTask { await Self.probe(host: host) }
                }
            }
        }
    }

    private static func probe(host: String) async -> DiscoveredServer? {
        guard let url = URL(string: "http://\(host):\(immichPort)") else { return nil }
        let alive = await ImmichClient.ping(serverURL: url, timeout: 1.5)
        return alive ? DiscoveredServer(url: url) : nil
    }
}
