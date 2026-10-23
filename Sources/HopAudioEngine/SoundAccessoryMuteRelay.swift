import Foundation

/// A bounded worker acknowledgement; closing a capture retires its token.
public final class SoundAccessoryMuteRelay: @unchecked Sendable {
    private final class Pending {
        let id = UUID().uuidString
        let token: String
        let signal = DispatchSemaphore(value: 0)
        var result = false
        init(_ token: String) { self.token = token }
    }
    private let lock = NSLock()
    private let writeLock = NSLock()
    private let write: (Data) throws -> Void
    private var token: String?
    private var pending: Pending?
    private var buffer = Data()
    public init(write: @escaping (Data) throws -> Void) { self.write = write }
    public func select(_ token: String?) {
        lock.lock(); defer { lock.unlock() }
        guard self.token != token else { return }
        self.token = token; pending?.signal.signal(); pending = nil
    }
    public func send(_ data: Data) throws {
        writeLock.lock(); defer { writeLock.unlock() }; try write(data)
    }
    public func request(_ value: Bool, token: String, timeout: Double = 0.75) -> Bool {
        lock.lock()
        guard self.token == token, pending == nil else { lock.unlock(); return false }
        let item = Pending(token); pending = item
        lock.unlock()
        do {
            var data = try JSONSerialization.data(withJSONObject: ["accessoryMute": value, "captureToken": token, "muteRequest": item.id])
            data.append(10); try send(data)
        } catch { lock.lock(); if pending === item { pending = nil }; lock.unlock(); return false }
        let completed = item.signal.wait(timeout: .now() + max(0, min(1, timeout))) == .success
        lock.lock(); defer { lock.unlock() }
        if pending === item { pending = nil }
        return completed && self.token == token && item.result
    }
    public func consume(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        guard buffer.count + data.count <= 65536 else { buffer.removeAll(); pending?.signal.signal(); pending = nil; return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newline); buffer.removeSubrange(...newline)
            guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  let item = pending, object["muteRequest"] as? String == item.id,
                  object["captureToken"] as? String == item.token else { continue }
            item.result = object["muteApplied"] as? Bool == true
            item.signal.signal()
        }
    }
}
