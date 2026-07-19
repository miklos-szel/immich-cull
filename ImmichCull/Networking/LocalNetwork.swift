import Foundation

enum LocalNetwork {
    /// Largest subnet we are willing to enumerate; anything bigger is narrowed
    /// to the /24 around the device so discovery stays quick.
    private static let maxScannedHosts: UInt32 = 1024

    private struct Interface {
        let address: UInt32
        let netmask: UInt32
    }

    /// IPv4 addresses of the device's Wi-Fi/Ethernet interfaces.
    static func localIPv4Addresses() -> [String] {
        interfaces().map { ipv4String($0.address) }
    }

    /// Other host addresses on the same subnets as this device.
    static func subnetHosts() -> [String] {
        var hosts: [String] = []
        var seen: Set<String> = []

        for interface in interfaces() {
            var network = interface.address & interface.netmask
            var broadcast = network | ~interface.netmask

            // Narrow oversized subnets (e.g. a /16) to a scannable /24.
            if broadcast - network > Self.maxScannedHosts {
                let mask24: UInt32 = 0xFFFF_FF00
                network = interface.address & mask24
                broadcast = network | ~mask24
            }
            guard broadcast > network + 1 else { continue }

            for value in (network + 1)..<broadcast where value != interface.address {
                let host = ipv4String(value)
                if seen.insert(host).inserted {
                    hosts.append(host)
                }
            }
        }
        return hosts
    }

    // MARK: Interface enumeration

    private static func interfaces() -> [Interface] {
        var result: [Interface] = []
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0 else { return [] }
        defer { freeifaddrs(ifaddrPointer) }

        var pointer = ifaddrPointer
        while let current = pointer {
            let interface = current.pointee
            pointer = interface.ifa_next

            let name = String(cString: interface.ifa_name)
            guard name.hasPrefix("en"),
                  let address = ipv4Value(interface.ifa_addr),
                  let netmask = ipv4Value(interface.ifa_netmask),
                  netmask != 0 else { continue }
            result.append(Interface(address: address, netmask: netmask))
        }
        return result
    }

    private static func ipv4Value(_ pointer: UnsafeMutablePointer<sockaddr>?) -> UInt32? {
        guard let pointer, pointer.pointee.sa_family == UInt8(AF_INET) else { return nil }
        return pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
            UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
        }
    }

    private static func ipv4String(_ value: UInt32) -> String {
        "\((value >> 24) & 0xFF).\((value >> 16) & 0xFF).\((value >> 8) & 0xFF).\(value & 0xFF)"
    }
}
