import Foundation

/// SPEC: docs/spec.md — "Network access". What the app may ask the filter.
@objc public protocol NetworkFilterXPC {
    /// Every sighting the filter holds, JSON-encoded `[NetworkSighting]`.
    func sightings(reply: @escaping (Data) -> Void)
}
