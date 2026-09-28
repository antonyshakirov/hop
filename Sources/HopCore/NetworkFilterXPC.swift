import Foundation

/// SPEC: docs/spec.md — "Network access". What the app may ask the filter.
@objc public protocol NetworkFilterXPC {
    /// Every sighting the filter holds, JSON-encoded `[NetworkSighting]`.
    func sightings(reply: @escaping (Data) -> Void)
    /// The calling app answers questions about new connections while on.
    func setAsking(_ on: Bool)
}

/// A JSON `NetworkSighting` in; "allow", "deny", or "" for no answer back.
@objc public protocol NetworkFilterAskerXPC {
    func ask(_ sighting: Data, reply: @escaping (String) -> Void)
}
