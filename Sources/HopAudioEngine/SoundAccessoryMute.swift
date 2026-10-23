import AVFoundation
import Foundation

/// Acknowledges a gesture only after the current microphone target accepts it.
public final class SoundAccessoryMuteGate: @unchecked Sendable {
    private struct Target {
        let token: UUID
        var muted: Bool
        let apply: (Bool) -> Bool
        let changed: (Bool) -> Void
    }
    private let lock = NSRecursiveLock()
    private var target: Target?
    public init() {}
    public func bind(_ token: UUID, muted: Bool, apply: @escaping (Bool) -> Bool, changed: @escaping (Bool) -> Void) {
        lock.lock(); defer { lock.unlock() }
        target = Target(token: token, muted: muted, apply: apply, changed: changed)
    }
    @discardableResult public func unbind(_ token: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard target?.token == token else { return false }
        target = nil; return true
    }
    public func request(_ muted: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let current = target else { return true }
        guard current.muted != muted else { return true }
        guard current.apply(muted), target?.token == current.token else { return false }
        target?.muted = muted
        current.changed(muted)
        return true
    }
    public func confirm(_ token: UUID, muted: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard target?.token == token, target?.muted != muted else { return }
        target?.muted = muted; target?.changed(muted)
    }
    public var muted: Bool {
        lock.lock(); defer { lock.unlock() }; return target?.muted ?? false
    }
}

/// Registers the public AirPods API without starting audio I/O or posting alerts.
public final class SoundAccessoryMute: @unchecked Sendable {
    public static let shared = SoundAccessoryMute()
    public let gate = SoundAccessoryMuteGate()
    private let lock = NSLock()
    private var installed = false
    private init() {}
    public func install() throws {
        lock.lock(); defer { lock.unlock() }
        guard !installed else { return }
        let gate = gate
        try AVAudioApplication.shared.setInputMuteStateChangeHandler { gate.request($0) }
        installed = true
    }
    public func bind(_ token: UUID, muted: Bool, apply: @escaping (Bool) -> Bool, changed: @escaping (Bool) -> Void) throws {
        try install()
        gate.bind(token, muted: muted, apply: apply, changed: changed)
        do { try publish(muted) }
        catch { gate.unbind(token); throw error }
    }
    public func unbind(_ token: UUID) {
        gate.unbind(token)
    }
    public func setMuted(_ value: Bool) -> Bool {
        guard gate.request(value) else { return false }
        do { try publish(value); return true } catch { return false }
    }
    public func publish(_ value: Bool) throws {
        if AVAudioApplication.shared.isInputMuted != value { try AVAudioApplication.shared.setInputMuted(value) }
    }
}
