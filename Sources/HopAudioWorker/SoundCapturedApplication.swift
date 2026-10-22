import AVFoundation
import CoreAudio
import HopAudioDSP
import HopAudioEngine
import HopCore

private enum SoundApplicationCaptureError: Error {
    case invalidSelection
    case identity(UInt32, String?)
    case tap(OSStatus)
    case format(Double, UInt32, UInt32)
    case aggregate(OSStatus)
    case stream(OSStatus)
}

@available(macOS 14.2, *)
final class SoundCapturedApplication {
    let channel: SoundAudioChannel
    private var tap = AudioObjectID(0)
    private var device = AudioObjectID(0)
    private var io: AudioDeviceIOProcID?
    init(_ configuration: SoundApplicationConfiguration) throws {
        guard SoundCallMixPolicy.allows(configuration.id), !configuration.processes.isEmpty,
              configuration.processes.count <= 32 else { throw SoundApplicationCaptureError.invalidSelection }
        for process in configuration.processes {
            let bundle = SoundHAL.string(process, kAudioProcessPropertyBundleID)
            guard let bundle, SoundCallMixPolicy.ownsProcess(bundle, selectedBundle: configuration.id) else {
                throw SoundApplicationCaptureError.identity(process, bundle)
            }
        }
        channel = try SoundAudioChannel(rate: 48000)
        hop_audio_compensate_clock(channel.pointer)
        channel.configure(configuration.settings)
        let description = CATapDescription(stereoMixdownOfProcesses: configuration.processes)
        description.name = "Hop Call Source"; description.isPrivate = true
        description.muteBehavior = .unmuted
        let created = AudioHardwareCreateProcessTap(description, &tap)
        guard created == noErr else { throw SoundApplicationCaptureError.tap(created) }
        do {
            guard let format = SoundHAL.value(tap, kAudioTapPropertyFormat, AudioStreamBasicDescription()),
                  format.mSampleRate == 48000, format.mChannelsPerFrame == 2,
                  format.mFormatID == kAudioFormatLinearPCM, format.mBitsPerChannel == 32,
                  format.mFormatFlags & kAudioFormatFlagIsFloat != 0 else {
                let format = SoundHAL.value(tap, kAudioTapPropertyFormat, AudioStreamBasicDescription()) ?? AudioStreamBasicDescription()
                throw SoundApplicationCaptureError.format(format.mSampleRate, format.mChannelsPerFrame, format.mFormatFlags)
            }
            let composition: [String: Any] = [kAudioAggregateDeviceNameKey: "Hop Call Source",
                kAudioAggregateDeviceUIDKey: "com.antonshakirov.hop.call." + UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: 1,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                                  kAudioSubTapDriftCompensationKey: true]]]
            let made = AudioHardwareCreateAggregateDevice(composition as CFDictionary, &device)
            guard made == noErr else { throw SoundApplicationCaptureError.aggregate(made) }
            let channel = channel, interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
            let ioStatus = AudioDeviceCreateIOProcIDWithBlock(&io, device, nil, { _, input, _, _, _ in
                let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                guard let first = buffers.first else { return }
                let stride = interleaved ? max(1, first.mNumberChannels) : 1
                _ = hop_audio_push(channel.pointer, input, first.mDataByteSize / 4 / stride)
            })
            guard ioStatus == noErr, let io else { throw SoundApplicationCaptureError.stream(ioStatus) }
            let startStatus = AudioDeviceStart(device, io)
            guard startStatus == noErr else { throw SoundApplicationCaptureError.stream(startStatus) }
        } catch { stop(); throw error }
    }
    func stop() {
        if let io { AudioDeviceStop(device, io); AudioDeviceDestroyIOProcID(device, io) }; io = nil
        if device != 0 { AudioHardwareDestroyAggregateDevice(device); device = 0 }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 }
    }
    deinit { stop() }
}
