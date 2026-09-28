import Foundation

/// SPEC: docs/spec.md — "Network access". What the app may ask the filter.
@objc public protocol NetworkFilterXPC {
    /// Every sighting the filter holds, JSON-encoded `[NetworkSighting]`.
    func sightings(reply: @escaping (Data) -> Void)
    /// The calling app answers questions about new connections while on.
    func setAsking(_ on: Bool)
}

/// What the filter may ask the app: a JSON `NetworkSighting` in, and the
/// answer back — "allow", "deny", or "" for no answer.
@objc public protocol NetworkFilterAskerXPC {
    func ask(_ sighting: Data, reply: @escaping (String) -> Void)
}
