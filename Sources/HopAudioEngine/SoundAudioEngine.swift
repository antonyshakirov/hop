import Foundation
import CoreAudio
import HopAudioDSP
import HopCore

public enum SoundAudioError: Error { case failed }

public enum SoundHAL {
    public static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    public static func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> T? {
        var result = initial, a = address(selector, scope: scope), size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &result) { AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0) }
        return status == noErr ? result : nil
    }
    public static func ids(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var a = address(selector), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &a, 0, nil, &size) == noErr,
              size > 0, size % 4 == 0, size < 65536 else { return [] }
        var result = [AudioObjectID](repeating: 0, count: Int(size) / 4)
        let status = result.withUnsafeMutableBytes { AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0.baseAddress!) }
        return status == noErr ? result : []
    }
    public static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var result: CFString?, a = address(selector), size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &result) { AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0) }
        return status == noErr ? result as String? : nil
    }
    public static func process(_ pid: pid_t) -> AudioObjectID? {
        ids(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList).first {
            value($0, kAudioProcessPropertyPID, pid_t(0)) == pid
        }
    }
    public static func device(_ uid: String) -> AudioObjectID? {
        var a = address(kAudioHardwarePropertyTranslateUIDToDevice), string = uid as CFString
        var id = AudioObjectID(0), size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &string) {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a,
                                      UInt32(MemoryLayout<CFString>.size), $0, &size, &id)
        }
        return status == noErr && id != 0 ? id : nil
    }
}

public final class SoundAudioChannel {
    public let pointer: OpaquePointer
    public let sampleRate: Double
    public init(rate: Double) throws {
        guard let pointer = hop_audio_create(rate) else { throw SoundAudioError.failed }
        self.pointer = pointer; sampleRate = rate
    }
    public func configure(_ settings: SoundChannelSettings) {
        hop_audio_configure(pointer, Float(settings.safeGain), settings.muted || !settings.active, settings.denoise, settings.bass)
    }
    deinit { hop_audio_destroy(pointer) }
}

