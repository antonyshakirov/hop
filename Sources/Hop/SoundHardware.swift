import CoreAudio
import Foundation
import HopCore

enum SoundFailure: Error, Equatable {
    case unsupported, missingDevice, system(Int32), permission, inputChanged, inputRemoval
}

@MainActor
protocol SoundHardware: AnyObject {
    func devices(_ direction: SoundDirection) -> [SoundDevice]
    func defaultUID(_ direction: SoundDirection) -> String?
    func select(_ uid: String, direction: SoundDirection) throws
    func setVolume(_ volume: Double, uid: String, direction: SoundDirection) throws
    func setVolumeAsync(_ volume: Double, uid: String, direction: SoundDirection) async throws
    func setMute(_ muted: Bool, uid: String, direction: SoundDirection) throws
    func watchMute(_ changed: @escaping () -> Void)
    func watch(_ changed: @escaping () -> Void)
    func watch(_ changed: @escaping () -> Void, outputVolumeChanged: @escaping () -> Void)
    func unwatch()
}

extension SoundHardware {
    func setVolumeAsync(_ volume: Double, uid: String, direction: SoundDirection) async throws {
        try Task.checkCancellation()
        try setVolume(volume, uid: uid, direction: direction)
    }
    func watch(_ changed: @escaping () -> Void, outputVolumeChanged: @escaping () -> Void) { watch(changed) }
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
    private var listeningOnly = false
    private var includeVolume = true
    private var changed: (() -> Void)?
    private var outputVolumeChanged: (() -> Void)?

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
                canMute: !controls(id, direction, selector: kAudioDevicePropertyMute, writable: true).isEmpty,
                isVirtual: read(id, address(kAudioDevicePropertyTransportType), initial: UInt32(0)) == kAudioDeviceTransportTypeVirtual)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    nonisolated private func defaultSelector(_ direction: SoundDirection) -> AudioObjectPropertySelector {
        direction == .input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
    }

    nonisolated func defaultUID(_ direction: SoundDirection) -> String? {
        read(AudioObjectID(kAudioObjectSystemObject), address(defaultSelector(direction)), initial: AudioObjectID(0))
            .flatMap(uid)
    }

    nonisolated func listeningMaster() -> SoundListeningMasterSnapshot {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let defaultAddress = address(kAudioHardwarePropertyDefaultOutputDevice)
        for _ in 0..<2 {
            guard let id = read(system, defaultAddress, initial: AudioObjectID(0)), let uid = uid(id) else { break }
            let scalarAddresses = controls(id, .output, selector: kAudioDevicePropertyVolumeScalar, writable: false)
            let scalars = scalarAddresses.compactMap { read(id, $0, initial: Float32(0)).map(Double.init) }
            let scalar = !scalars.isEmpty && scalars.count == scalarAddresses.count && scalars.allSatisfy { $0.isFinite }
                ? scalars.reduce(0, +) / Double(scalars.count) : nil
            let dbAddresses = controls(id, .output, selector: kAudioDevicePropertyVolumeDecibels, writable: false)
            let amplitudes: [Double] = dbAddresses.compactMap { a in
                guard let db = read(id, a, initial: Float32(0)), db.isFinite else { return nil }
                var rangeAddress = a; rangeAddress.mSelector = kAudioDevicePropertyVolumeRangeDecibels
                guard let range = read(id, rangeAddress, initial: AudioValueRange(mMinimum: 0, mMaximum: 0)),
                      range.mMinimum.isFinite, range.mMaximum.isFinite, range.mMinimum < range.mMaximum,
                      Double(db) >= range.mMinimum, Double(db) <= range.mMaximum else { return nil }
                return SoundListeningMasterSnapshot(uid: uid, scalar: nil, muted: nil,
                    decibels: Double(db), maximumDB: range.mMaximum).attenuation
            }
            let mapped: [Double] = zip(scalarAddresses, scalars).compactMap { a, scalar in
                var conversion = a; conversion.mSelector = kAudioDevicePropertyVolumeScalarToDecibels
                guard let current = read(id, conversion, initial: Float32(scalar)),
                      let maximum = read(id, conversion, initial: Float32(1)),
                      current.isFinite, maximum.isFinite else { return nil }
                return SoundListeningMasterSnapshot(uid: uid, scalar: scalar, muted: nil,
                    decibels: Double(current), maximumDB: Double(maximum)).attenuation
            }
            let dbLevel = !amplitudes.isEmpty && amplitudes.count == dbAddresses.count
                ? amplitudes.reduce(0, +) / Double(amplitudes.count) : nil
            let mappedLevel = !mapped.isEmpty && mapped.count == scalarAddresses.count
                ? mapped.reduce(0, +) / Double(mapped.count) : nil
            let attenuation = scalar == 0 ? 0 : (dbLevel ?? mappedLevel ?? scalar)
            let muteAddresses = controls(id, .output, selector: kAudioDevicePropertyMute, writable: false)
            let mutes = muteAddresses.compactMap { read(id, $0, initial: UInt32(0)) }
            let muted = !mutes.isEmpty && mutes.count == muteAddresses.count ? mutes.allSatisfy { $0 != 0 } : nil
            guard read(system, defaultAddress, initial: AudioObjectID(0)) == id else { continue }
            return SoundListeningMasterSnapshot(uid: uid, scalar: attenuation, muted: muted)
        }
        return SoundListeningMasterSnapshot(uid: nil, scalar: nil, muted: nil)
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
        try setVolume(volume, uid: uid, direction: direction, validate: {})
    }
    nonisolated private func setVolume(_ volume: Double, uid: String, direction: SoundDirection,
                                      validate: () throws -> Void) throws {
        let id = try resolve(uid, direction)
        let addresses = controls(id, direction, selector: kAudioDevicePropertyVolumeScalar, writable: true)
        let original = addresses.compactMap { read(id, $0, initial: Float32(0)) }
        guard original.count == addresses.count,
              let adjusted = SoundGain.adjusted(original.map(Double.init), target: volume) else {
            throw SoundFailure.unsupported
        }
        try validate()
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

    func watch(_ changed: @escaping () -> Void) { watch(changed, outputVolumeChanged: changed) }
    func watch(_ changed: @escaping () -> Void, outputVolumeChanged: @escaping () -> Void) {
        unwatch()
        self.changed = changed; self.outputVolumeChanged = outputVolumeChanged
        includeVolume = true; listeningOnly = false
        installListeners()
    }

    func watchListeningMaster(_ changed: @escaping () -> Void) {
        unwatch(); self.changed = changed; outputVolumeChanged = changed
        includeVolume = true; listeningOnly = true
        installListeners()
    }

    func watchMute(_ changed: @escaping () -> Void) {
        unwatch()
        self.changed = changed
        includeVolume = false; listeningOnly = false
        installListeners()
    }

    func setVolumeAsync(_ volume: Double, uid: String, direction: SoundDirection) async throws {
        let write = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard self.defaultUID(direction) == uid else { throw SoundFailure.missingDevice }
            try self.setVolume(volume, uid: uid, direction: direction) {
                try Task.checkCancellation()
                guard self.defaultUID(direction) == uid else { throw SoundFailure.missingDevice }
            }
        }
        try await withTaskCancellationHandler { try await write.value } onCancel: { write.cancel() }
    }

    private func installListeners() {
        let ids = deviceIDs().filter { !isPrivateAggregate($0) }.sorted()
        guard observedDeviceIDs != ids else { return }
        observedDeviceIDs = ids
        observations.removeAll()
        func observe(_ id: AudioObjectID, _ a: AudioObjectPropertyAddress, rebuild: Bool = false,
                     outputVolume: Bool = false) {
            if let token = SoundPropertyObservation(object: id, address: a, block: { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self, self.changed != nil else { return }
                    if rebuild { self.installListeners() }
                    if outputVolume { (self.outputVolumeChanged ?? self.changed)?() }
                    else { self.changed?() }
                }
            }) { observations.append(token) }
        }
        let system = AudioObjectID(kAudioObjectSystemObject)
        observe(system, address(kAudioHardwarePropertyDevices), rebuild: true)
        observe(system, address(kAudioHardwarePropertyDefaultOutputDevice))
        if !listeningOnly { observe(system, address(kAudioHardwarePropertyDefaultInputDevice)) }
        for id in ids {
            observe(id, address(kAudioDevicePropertyDeviceIsAlive), rebuild: true)
            for direction in (listeningOnly ? [.output] : SoundDirection.allCases) {
                let selectors = listeningOnly ? [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyVolumeDecibels,
                    kAudioDevicePropertyMute] : (includeVolume ? [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] : [kAudioDevicePropertyMute])
                for selector in selectors {
                    for a in controls(id, direction, selector: selector, writable: false) {
                        observe(id, a, outputVolume: direction == .output && selector == kAudioDevicePropertyVolumeScalar)
                    }
                }
            }
        }
    }

    func unwatch() { changed = nil; outputVolumeChanged = nil; observations.removeAll(); observedDeviceIDs = nil }
}
