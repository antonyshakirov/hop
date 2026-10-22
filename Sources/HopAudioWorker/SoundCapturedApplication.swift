import AVFoundation
import CoreAudio
import HopAudioDSP
import HopAudioEngine
import HopCore

@available(macOS 14.2, *)
final class SoundCapturedApplication {
    let channel: SoundAudioChannel
    private var tap = AudioObjectID(0)
    private var device = AudioObjectID(0)
    private var io: AudioDeviceIOProcID?
    init(_ configuration: SoundApplicationConfiguration) throws {
        guard SoundCallMixPolicy.allows(configuration.id), !configuration.processes.isEmpty,
              configuration.processes.count <= 32,
              configuration.processes.allSatisfy({ process in
                  guard let bundle = SoundHAL.string(process, kAudioProcessPropertyBundleID) else { return false }
                  return SoundCallMixPolicy.ownsProcess(bundle, selectedBundle: configuration.id)
              }) else { throw SoundAudioError.failed }
        channel = try SoundAudioChannel(rate: 48000)
        hop_audio_compensate_clock(channel.pointer)
        channel.configure(configuration.settings)
        let description = CATapDescription(stereoMixdownOfProcesses: configuration.processes)
        description.name = "Hop Call Source"; description.isPrivate = true
        description.muteBehavior = .unmuted
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr else { throw SoundAudioError.failed }
        do {
            guard let format = SoundHAL.value(tap, kAudioTapPropertyFormat, AudioStreamBasicDescription()),
                  format.mSampleRate == 48000, format.mChannelsPerFrame == 2,
                  format.mFormatID == kAudioFormatLinearPCM, format.mBitsPerChannel == 32,
                  format.mFormatFlags & kAudioFormatFlagIsFloat != 0 else { throw SoundAudioError.failed }
            let composition: [String: Any] = [kAudioAggregateDeviceNameKey: "Hop Call Source",
                kAudioAggregateDeviceUIDKey: "com.antonshakirov.hop.call." + UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: 1,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                                  kAudioSubTapDriftCompensationKey: true]]]
            guard AudioHardwareCreateAggregateDevice(composition as CFDictionary, &device) == noErr else { throw SoundAudioError.failed }
            let channel = channel, interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
            guard AudioDeviceCreateIOProcIDWithBlock(&io, device, nil, { _, input, _, _, _ in
                let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                guard let first = buffers.first else { return }
                let stride = interleaved ? max(1, first.mNumberChannels) : 1
                _ = hop_audio_push(channel.pointer, input, first.mDataByteSize / 4 / stride)
            }) == noErr, let io, AudioDeviceStart(device, io) == noErr else { throw SoundAudioError.failed }
        } catch { stop(); throw error }
    }
    func stop() {
        if let io { AudioDeviceStop(device, io); AudioDeviceDestroyIOProcID(device, io) }; io = nil
        if device != 0 { AudioHardwareDestroyAggregateDevice(device); device = 0 }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 }
    }
    deinit { stop() }
}
