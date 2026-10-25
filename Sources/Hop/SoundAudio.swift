import AppKit
import AVFoundation
import CoreAudio
import HopAudioDSP
import HopCore
import HopAudioEngine

final class SoundHALObservation {
    private let id: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let block: AudioObjectPropertyListenerBlock
    init?(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, changed: @escaping () -> Void) {
        self.id = id; address = SoundHAL.address(selector)
        block = { _, _ in changed() }
        guard AudioObjectAddPropertyListenerBlock(id, &address, .main, block) == noErr else { return nil }
    }
    deinit { AudioObjectRemovePropertyListenerBlock(id, &address, .main, block) }
}

@available(macOS 14.2, *)
final class SoundProcessTap {
    private static var virtualUID: String { "com.antonshakirov.hop.audio." + (Bundle.main.bundleIdentifier ?? "Hop") + ".input" }
    private static let resourceKey = "soundMixerVirtualResource"
    private let publicInput: Bool
    private let tapUID: String
    private let description: CATapDescription
    private(set) var tap: AudioObjectID = 0
    private(set) var aggregate: AudioObjectID = 0
    let uid: String
    let format: AVAudioFormat
    private var io: AudioDeviceIOProcID?
    private var channel: SoundAudioChannel?

    init(processes: [AudioObjectID], name: String, publicInput: Bool = false, holdSourceMuted: Bool = false, warmupUnmuted: Bool = false) throws {
        guard !processes.isEmpty else { throw SoundFailure.missingDevice }
        self.publicInput = publicInput
        uid = publicInput ? Self.virtualUID : "com.antonshakirov.hop.audio." + UUID().uuidString
        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        self.description = description
        description.name = name; description.isPrivate = !publicInput
        tapUID = description.uuid.uuidString
        description.muteBehavior = publicInput || holdSourceMuted ? .muted : warmupUnmuted ? .unmuted : .mutedWhenTapped
        var tap = AudioObjectID(0)
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr else { throw SoundFailure.system(-1) }
        self.tap = tap
        guard var asbd = SoundHAL.value(tap, kAudioTapPropertyFormat, AudioStreamBasicDescription()),
              asbd.mFormatID == kAudioFormatLinearPCM, asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              asbd.mBitsPerChannel == 32, asbd.mChannelsPerFrame == 2,
              let format = AVAudioFormat(streamDescription: &asbd) else {
            AudioHardwareDestroyProcessTap(tap); self.tap = 0; throw SoundFailure.unsupported
        }
        self.format = format
        let composition: [String: Any] = [kAudioAggregateDeviceNameKey: name,
            kAudioAggregateDeviceUIDKey: uid, kAudioAggregateDeviceIsPrivateKey: publicInput ? 0 : 1,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                             kAudioSubTapDriftCompensationKey: true]]]
        var aggregate = AudioObjectID(0)
        guard AudioHardwareCreateAggregateDevice(composition as CFDictionary, &aggregate) == noErr else {
            AudioHardwareDestroyProcessTap(tap); self.tap = 0; throw SoundFailure.system(-1)
        }
        self.aggregate = aggregate
        if publicInput {
            do { try startPublicInput() } catch {
                stop()
                AudioHardwareDestroyAggregateDevice(aggregate); self.aggregate = 0
                AudioHardwareDestroyProcessTap(tap); self.tap = 0
                throw error
            }
            UserDefaults.standard.set(["uid": uid, "tap": tapUID, "owner": Int(ProcessInfo.processInfo.processIdentifier)], forKey: Self.resourceKey)
        }
    }

    // WORKAROUND: an AVAudioEngine client does not start a tap-only public input.
    // Live regression: the client must receive frames without another HAL consumer.
    private func startPublicInput() throws {
        var io: AudioDeviceIOProcID?
        let created = AudioDeviceCreateIOProcIDWithBlock(&io, aggregate, nil) { _, _, _, _, _ in }
        guard created == noErr, let io else { throw SoundFailure.system(created) }
        self.io = io
        let started = AudioDeviceStart(aggregate, io)
        guard started == noErr else { throw SoundFailure.system(started) }
    }

    func start(_ channel: SoundAudioChannel) throws {
        self.channel = channel
        let interleaved = format.isInterleaved
        var io: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&io, aggregate, nil) { _, input, _, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let first = buffers.first else { return }
            let bytesPerFrame = UInt32(MemoryLayout<Float>.size) * (interleaved ? first.mNumberChannels : 1)
            guard bytesPerFrame > 0 else { return }
            _ = hop_audio_push(channel.pointer, input, first.mDataByteSize / bytesPerFrame)
        }
        guard status == noErr, let io else { throw SoundFailure.system(-1) }
        self.io = io
        if Task.isCancelled { stop(); throw CancellationError() }
        guard AudioDeviceStart(aggregate, io) == noErr else { stop(); throw SoundFailure.permission }
    }
    func setSourceMuted(_ muted: Bool) throws {
        let behavior: CATapMuteBehavior = muted ? .muted : .unmuted
        guard description.muteBehavior != behavior else { return }
        let previous = description.muteBehavior
        description.muteBehavior = behavior
        var value = description, address = SoundHAL.address(kAudioTapPropertyDescription)
        let status = withUnsafePointer(to: &value) {
            AudioObjectSetPropertyData(tap, &address, 0, nil, UInt32(MemoryLayout<CATapDescription>.size), $0)
        }
        guard status == noErr else { description.muteBehavior = previous; throw SoundFailure.system(status) }
    }
    func stop() {
        if let io { AudioDeviceStop(aggregate, io); AudioDeviceDestroyIOProcID(aggregate, io) }
        io = nil; channel = nil
    }
    func release() {
        stop()
        if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate); aggregate = 0 }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 }
        if publicInput, let resource = UserDefaults.standard.dictionary(forKey: Self.resourceKey), resource["tap"] as? String == tapUID {
            UserDefaults.standard.removeObject(forKey: Self.resourceKey)
        }
    }
    deinit { release() }
    static func cleanStaleVirtualInput() {
        guard let resource = UserDefaults.standard.dictionary(forKey: resourceKey),
              resource["uid"] as? String == virtualUID, let owner = resource["owner"] as? Int,
              owner > 0, owner <= Int(Int32.max), kill(pid_t(owner), 0) != 0, errno == ESRCH else { return }
        if let device = SoundHAL.device(virtualUID) { AudioHardwareDestroyAggregateDevice(device) }
        if let uid = resource["tap"] as? String, UUID(uuidString: uid) != nil {
            var string = uid as CFString, a = SoundHAL.address(kAudioHardwarePropertyTranslateUIDToTap)
            var id: AudioObjectID = 0, size = UInt32(MemoryLayout<AudioObjectID>.size)
            _ = withUnsafePointer(to: &string) {
                AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a,
                                          UInt32(MemoryLayout<CFString>.size), $0, &size, &id)
            }
            if id != 0 { AudioHardwareDestroyProcessTap(id) }
        }
        UserDefaults.standard.removeObject(forKey: resourceKey)
    }
}
