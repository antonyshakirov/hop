import Foundation

// SPEC: docs/spec.md — Output mixer handoff, off-main engine destruction.
final class SoundOutputEngineLifetime<Resource: AnyObject> {
    private static var retirementQueue: DispatchQueue { SoundOutputEngineRetirement.queue }
    private let resource: Unmanaged<Resource>

    init(make: () -> Resource) { resource = .passRetained(make()) }

    // The resource must not escape the synchronous borrowing closure.
    func withResource<Result>(_ body: (Resource) throws -> Result) rethrows -> Result {
        try withExtendedLifetime(self) { try body(resource.takeUnretainedValue()) }
    }

    deinit {
        let resource = resource
        Self.retirementQueue.async { resource.release() }
    }
}

private enum SoundOutputEngineRetirement {
    static let queue = DispatchQueue(label: "hop.sound.output-retirement", qos: .utility)
}
