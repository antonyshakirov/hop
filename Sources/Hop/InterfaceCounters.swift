import Darwin
import Foundation

/// How much a network interface has carried, straight from the kernel's own
/// counters.
///
/// `getifaddrs` rather than a command: this is read every couple of seconds for as
/// long as a tunnel is up, and launching a process on that cadence to learn two
/// numbers would cost more than everything else the module does put together.
/// This way a reading takes microseconds and spawns nothing.
enum InterfaceCounters {

    /// PACKETS, not bytes, and that is deliberate. Measured against `netstat -ibn`
    /// on 2026-07-31: the packet counters agree to the unit, while the BYTE
    /// counters this call reports are rounded down to a multiple of 1024 and lag
    /// behind. On a quiet but healthy tunnel that rounding can swallow a whole
    /// exchange, which would read as a tunnel bringing nothing back — the one
    /// mistake this module must not make. A single packet is unambiguous.
    ///
    /// nil when there is no interface by that name, which is itself worth knowing:
    /// a tunnel going down takes its `utun` with it.
    static func read(_ name: String) -> (inPackets: UInt64, outPackets: UInt64)? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return nil }
        defer { freeifaddrs(head) }
        var cursor = head
        while let entry = cursor {
            cursor = entry.pointee.ifa_next
            // The counters hang off the LINK-layer entry, not the IPv4 one: the
            // same interface is listed once per address family and only this one
            // carries an `if_data`.
            guard let address = entry.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  String(cString: entry.pointee.ifa_name) == name,
                  let data = entry.pointee.ifa_data else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            return (UInt64(stats.ifi_ipackets), UInt64(stats.ifi_opackets))
        }
        return nil
    }
}
