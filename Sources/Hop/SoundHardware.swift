import CoreAudio
import Foundation
import HopCore

enum SoundFailure: Error, Equatable {
    case unsupported, missingDevice, system(Int32), permission, inputChanged
}

@MainActor
protocol SoundHardware: AnyObject {
    func devices(_ direction: SoundDirection) -> [SoundDevice]
    func defaultUID(_ direction: SoundDirection) -> String?
    func select(_ uid: String, direction: SoundDirection) throws
    func setVolume(_ volume: Double, uid: String, direction: SoundDirection) throws
    func setMute(_ muted: Bool, uid: String, direction: SoundDirection) throws
    func watchMute(_ changed: @escaping () -> Void)
    func watch(_ changed: @escaping () -> Void)
    func unwatch()
}

extension SoundHardware {
    func watchMute(_ changed: @escaping () -> Void) { watch(changed) }
}

private final class SoundPropertyObservation {
    let object: AudioObjectID
    var address: AudioObjectPropertyAddress
    let block: AudioObjectPropertyListenerBlock

    init?(object: AudioObjectID, address: AudioObjectPropertyAddress,
          block: @escaping AudioObjectPropertyListenerBlock) {
        self.object = object
        self.address = address
        self.block = block
        guard AudioObjectAddPropertyListenerBlock(object, &self.address, .main, block) == noErr
        else { return nil }
    }

    deinit { AudioObjectRemovePropertyListenerBlock(object, &address, .main, block) }
}

@MainActor
final class CoreSoundHardware: SoundHardware {
    private var observations: [SoundPropertyObservation] = []
    private var observedDeviceIDs: [AudioObjectID]?
    private var includeVolume = true
    private var changed: (() -> Void)?

    nonisolated private func address(_ selector: AudioObjectPropertySelector,
                         _ direction: SoundDirection? = nil,
                         element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
            mScope: direction.map { $0 == .input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput }
                ?? kAudioObjectPropertyScopeGlobal, mElement: element)
    }

    nonisolated private func read<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress,
                         initial: T) -> T? {
        var a = address
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0)
        }
        return status == noErr ? value : nil
    }

    nonisolated private func deviceIDs() -> [AudioObjectID] {
        var a = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a,
                                            0, nil, &size) == noErr else { return [] }
        guard size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let status = ids.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, $0.baseAddress!)
        }
        return status == noErr ? ids : []
    }

    nonisolated private func channels(_ id: AudioObjectID, _ direction: SoundDirection) -> Int {
        var a = address(kAudioDevicePropertyStreamConfiguration, direction)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, raw) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
            .reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    nonisolated private func uid(_ id: AudioObjectID) -> String? {
        read(id, address(kAudioDevicePropertyDeviceUID), initial: "" as CFString).map { $0 as String }
    }

    nonisolated func objectID(_ uid: String, direction: SoundDirection) throws -> AudioObjectID {
        try resolve(uid, direction)
    }

    nonisolated private func resolve(_ uid: String, _ direction: SoundDirection) throws -> AudioObjectID {
        guard let id = deviceIDs().first(where: {
            self.uid($0) == uid && channels($0, direction) > 0
                && read($0, address(kAudioDevicePropertyDeviceIsAlive), initial: UInt32(0)) == 1
        }) else { throw SoundFailure.missingDevice }
        return id
    }

    nonisolated private func controls(_ id: AudioObjectID, _ direction: SoundDirection,
                          selector: AudioObjectPropertySelector, writable: Bool) -> [AudioObjectPropertyAddress] {
        func usable(_ a: AudioObjectPropertyAddress) -> Bool {
            var a = a
            guard AudioObjectHasProperty(id, &a) else { return false }
            if !writable { return true }
            var canSet: DarwinBoolean = false
            return AudioObjectIsPropertySettable(id, &a, &canSet) == noErr && canSet.boolValue
        }
        let main = address(selector, direction)
        if usable(main) { return [main] }
        let count = channels(id, direction)
        guard count > 0, count <= 256 else { return [] }
        let all = (1...count).map { address(selector, direction, element: UInt32($0)) }
        // SPEC: docs/spec.md — "Sound": do not expose a partial stereo control.
        return all.allSatisfy(usable) ? all : []
    }

    nonisolated private func isPrivateAggregate(_ id: AudioObjectID) -> Bool {
        guard read(id, address(kAudioObjectPropertyClass), initial: AudioClassID(0)) == kAudioAggregateDeviceClassID,
              let composition = read(id, address(kAudioAggregateDevicePropertyComposition), initial: [:] as CFDictionary)
                as? [String: Any] else { return false }
        return (composition[kAudioAggregateDeviceIsPrivateKey] as? NSNumber)?.boolValue == true
    }

    nonisolated func devices(_ direction: SoundDirection) -> [SoundDevice] {
        deviceIDs().compactMap { id in
            guard !isPrivateAggregate(id), channels(id, direction) > 0, let uid = uid(id), !uid.isEmpty,
                  read(id, address(kAudioDevicePropertyDeviceIsAlive), initial: UInt32(0)) == 1 else { return nil }
            let volumeAddresses = controls(id, direction, selector: kAudioDevicePropertyVolumeScalar, writable: false)
            let volume = volumeAddresses
                .compactMap { read(id, $0, initial: Float32(0)).map(Double.init) }
                .filter { $0.isFinite && (0...1).contains($0) }
            let muteAddresses = controls(id, direction, selector: kAudioDevicePropertyMute, writable: false)
            let mute = muteAddresses
                .compactMap { read(id, $0, initial: UInt32(0)) }
            return SoundDevice(uid: uid,
                name: read(id, address(kAudioObjectPropertyName), initial: "" as CFString).map { $0 as String } ?? uid,
                volume: volume.isEmpty || volume.count != volumeAddresses.count ? nil : volume.reduce(0, +) / Double(volume.count),
                muted: mute.isEmpty || mute.count != muteAddresses.count ? nil : mute.allSatisfy { $0 != 0 },
                canChangeVolume: !controls(id, direction, selector: kAudioDevicePropertyVolumeScalar, writable: true).isEmpty,
                canMute: !controls(id, direction, selector: kAudioDevicePropertyMute, writable: true).isEmpty)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    nonisolated private func defaultSelector(_ direction: SoundDirection) -> AudioObjectPropertySelector {
        direction == .input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
    }

    nonisolated func defaultUID(_ direction: SoundDirection) -> String? {
        read(AudioObjectID(kAudioObjectSystemObject), address(defaultSelector(direction)), initial: AudioObjectID(0))
            .flatMap(uid)
    }

    nonisolated func select(_ uid: String, direction: SoundDirection) throws {
        let id = try resolve(uid, direction)
        try write(id, object: AudioObjectID(kAudioObjectSystemObject), address: address(defaultSelector(direction)))
    }

    nonisolated private func write<T>(_ value: T, object: AudioObjectID, address: AudioObjectPropertyAddress) throws {
        var a = address
        var value = value
        let status = withUnsafePointer(to: &value) {
            AudioObjectSetPropertyData(object, &a, 0, nil, UInt32(MemoryLayout<T>.size), $0)
        }
        guard status == noErr else { throw SoundFailure.system(status) }
    }

    nonisolated private func transaction<T>(_ values: [T], originals: [T], object: AudioObjectID,
                                addresses: [AudioObjectPropertyAddress]) throws {
        try SoundControlTransaction.apply(values, originals: originals) { i, value in
            try write(value, object: object, address: addresses[i])
        }
    }

    nonisolated func setVolume(_ volume: Double, uid: String, direction: SoundDirection) throws {
        let id = try resolve(uid, direction)
        let addresses = controls(id, direction, selector: kAudioDevicePropertyVolumeScalar, writable: true)
        let original = addresses.compactMap { read(id, $0, initial: Float32(0)) }
        guard original.count == addresses.count,
              let adjusted = SoundGain.adjusted(original.map(Double.init), target: volume) else {
            throw SoundFailure.unsupported
        }
        try transaction(adjusted.map(Float32.init), originals: original, object: id, addresses: addresses)
    }

    nonisolated func setMute(_ muted: Bool, uid: String, direction: SoundDirection) throws {
        let id = try resolve(uid, direction)
        let addresses = controls(id, direction, selector: kAudioDevicePropertyMute, writable: true)
        let original = addresses.compactMap { read(id, $0, initial: UInt32(0)) }
        guard !addresses.isEmpty, original.count == addresses.count else { throw SoundFailure.unsupported }
        try transaction(addresses.map { _ in UInt32(muted ? 1 : 0) }, originals: original,
                        object: id, addresses: addresses)
    }

    func watch(_ changed: @escaping () -> Void) {
        unwatch()
        self.changed = changed
        includeVolume = true
        installListeners()
    }

    func watchMute(_ changed: @escaping () -> Void) {
        unwatch()
        self.changed = changed
        includeVolume = false
        installListeners()
    }

    func setVolumeAsync(_ volume: Double, uid: String, direction: SoundDirection) async throws {
        try await Task.detached {
            guard self.defaultUID(direction) == uid else { throw SoundFailure.missingDevice }
            try self.setVolume(volume, uid: uid, direction: direction)
        }.value
    }

    private func installListeners() {
        let ids = deviceIDs().filter { !isPrivateAggregate($0) }.sorted()
        guard observedDeviceIDs != ids else { return }
        observedDeviceIDs = ids
        observations.removeAll()
        func observe(_ id: AudioObjectID, _ a: AudioObjectPropertyAddress, rebuild: Bool = false) {
            if let token = SoundPropertyObservation(object: id, address: a, block: { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self, self.changed != nil else { return }
                    if rebuild { self.installListeners() }
                    self.changed?()
                }
            }) { observations.append(token) }
        }
        let system = AudioObjectID(kAudioObjectSystemObject)
        observe(system, address(kAudioHardwarePropertyDevices), rebuild: true)
        observe(system, address(kAudioHardwarePropertyDefaultOutputDevice))
        observe(system, address(kAudioHardwarePropertyDefaultInputDevice))
        for id in ids {
            observe(id, address(kAudioDevicePropertyDeviceIsAlive), rebuild: true)
            for direction in SoundDirection.allCases {
                for selector in (includeVolume ? [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] : [kAudioDevicePropertyMute]) {
                    for a in controls(id, direction, selector: selector, writable: false) { observe(id, a) }
                }
            }
        }
    }

    func unwatch() { changed = nil; observations.removeAll(); observedDeviceIDs = nil }
}
