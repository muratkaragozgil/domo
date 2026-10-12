import Darwin
import Foundation

/// The Mac's own IPv4 subnets, for finding devices that don't announce
/// themselves. Wi-Fi and Ethernet only; VM bridges and tunnels are skipped.
nonisolated enum LocalNetwork {
    /// Every other address on each subnet, nearest-first by interface.
    /// Subnets larger than /22 (1022 hosts) are skipped rather than swept.
    static func neighborHosts() -> [String] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }

        var hosts: [String] = []
        var seenNetworks: Set<UInt32> = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            let name = String(cString: entry.pointee.ifa_name)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0,
                  name.hasPrefix("en"),
                  let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  let netmask = entry.pointee.ifa_netmask
            else { continue }

            let own = ipv4(address)
            let mask = ipv4(netmask)
            let prefix = mask.nonzeroBitCount
            guard (22...30).contains(prefix) else { continue }
            let network = own & mask
            guard seenNetworks.insert(network).inserted else { continue }

            for host in (network + 1)..<(network | ~mask) where host != own {
                hosts.append(dotted(host))
            }
        }
        return hosts
    }

    private static func ipv4(_ address: UnsafeMutablePointer<sockaddr>) -> UInt32 {
        address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
    }

    private static func dotted(_ address: UInt32) -> String {
        "\(address >> 24 & 0xFF).\(address >> 16 & 0xFF).\(address >> 8 & 0xFF).\(address & 0xFF)"
    }
}
