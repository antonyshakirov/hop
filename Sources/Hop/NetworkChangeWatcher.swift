import Foundation
import SystemConfiguration
import os

/// Tells the module the moment macOS moves anything about the network.
///
/// This is the same subsystem `scutil` reads, taken from the other end: rather
/// than asking every so often what the state is, we are told when it changes. A
/// tunnel coming up publishes its service's addresses here and one going down
/// withdraws them, both within milliseconds — including the case no amount of
/// polling the interfaces can see, a session the system has dropped whose `utun`
/// is still standing.
///
/// Read-only and unentitled: watching the store asks the user for nothing. It is
/// also cheaper than the poll it replaces, since a Mac whose network is not doing
/// anything wakes nobody up.
///
/// Nothing here is load-bearing on its own. Every rule about what to do with a
/// change lives in `VPNWatchCadence`, where it can be tested; this is the wire.
final class NetworkChangeWatcher {
    private nonisolated static let log = Logger(subsystem: "com.antonshakirov.hop", category: "VPN")

    /// The callback the C function is handed a pointer to. Held for as long as the
    /// store is, since the pointer is unretained.
    private final class Sink {
        let fire: @Sendable () -> Void
        init(_ fire: @escaping @Sendable () -> Void) { self.fire = fire }
    }

    private let sink: Sink
    private let queue = DispatchQueue(label: "com.antonshakirov.hop.network-watch")
    private var store: SCDynamicStore?

    /// nil when the store cannot be watched, which leaves the caller on its timer
    /// alone. Nothing is broken in that case, only slower.
    init?(onChange: @escaping @Sendable () -> Void) {
        sink = Sink(onChange)
        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(sink).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        guard let store = SCDynamicStoreCreate(
            nil, "com.antonshakirov.hop" as CFString,
            { _, _, info in
                guard let info else { return }
                Unmanaged<Sink>.fromOpaque(info).takeUnretainedValue().fire()
            },
            &context
        ) else {
            Self.log.error("network watch unavailable, timer only")
            return nil
        }
        // The service entities rather than the interfaces: a VPN publishes its
        // addresses against the SERVICE, which is the one thing that is true of
        // every configuration whatever the vendor built it on. IPv6, PPP and IPSec
        // alongside IPv4 because the older protocols the module also lists — a
        // corporate L2TP, an IKEv2 — announce themselves under their own.
        let patterns = [kSCEntNetIPv4, kSCEntNetIPv6, kSCEntNetPPP, kSCEntNetIPSec].map {
            SCDynamicStoreKeyCreateNetworkServiceEntity(
                nil, kSCDynamicStoreDomainState, kSCCompAnyRegex, $0)
        }
        // The global keys carry the default route (State), which a full tunnel
        // takes over, and the service order (Setup), which is what changes when a
        // service is switched in or out of the network set — including by Hop.
        let keys = [
            SCDynamicStoreKeyCreateNetworkGlobalEntity(nil, kSCDynamicStoreDomainState, kSCEntNetIPv4),
            SCDynamicStoreKeyCreateNetworkGlobalEntity(nil, kSCDynamicStoreDomainSetup, kSCEntNetIPv4),
        ]
        guard SCDynamicStoreSetNotificationKeys(store, keys as CFArray, patterns as CFArray) else {
            Self.log.error("network watch keys refused, timer only")
            return nil
        }
        SCDynamicStoreSetDispatchQueue(store, queue)
        self.store = store
    }

    deinit {
        if let store { SCDynamicStoreSetDispatchQueue(store, nil) }
    }
}
