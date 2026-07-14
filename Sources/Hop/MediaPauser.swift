import AppKit
import CoreAudio

/// "Pause media on finish": a timer that rang out pauses the current
/// playback (Music, Spotify, YouTube in a tab — whatever holds Now
/// Playing), so the timer alert sounds in silence.
@MainActor
enum MediaPauser {
    static let settingKey = "timerPausesMedia"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: settingKey)
    }

    /// Called BEFORE the timer alert — otherwise our own ring would count
    /// as playback in the "is anything playing" check.
    static func pauseIfEnabled() {
        guard isEnabled else { return }
        // if nothing is going through the output device right now, leave it
        // alone: a toggle command on silence would START the music instead
        guard isAudioRunning() else { return }
        if sendMediaRemotePause() { return }
        sendMediaKeyToggle()
    }

    /// Public CoreAudio: is ANYONE playing through the output device.
    private static func isAudioRunning() -> Bool {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        ) == noErr, deviceID != 0 else { return false }

        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &running) == noErr
        else { return false }
        return running != 0
    }

    /// MediaRemote: a proper "pause" command (not a toggle).
    /// The framework is private — load it dynamically; if the system refuses,
    /// fall back quietly to the media key.
    private static func sendMediaRemotePause() -> Bool {
        typealias SendCommand = @convention(c) (Int32, AnyObject?) -> Bool
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY
        ) else { return false }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "MRMediaRemoteSendCommand") else { return false }
        let send = unsafeBitCast(symbol, to: SendCommand.self)
        return send(1, nil) // 1 = kMRPause
    }

    /// Fallback path: the system media key ⏯ (a toggle — which is exactly
    /// why we guard with isAudioRunning above).
    private static func sendMediaKeyToggle() {
        let NX_KEYTYPE_PLAY: UInt32 = 16
        func post(down: Bool) {
            let flags: UInt32 = down ? 0x0A00 : 0x0B00
            let data1 = Int((NX_KEYTYPE_PLAY << 16) | flags)
            guard let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: data1, data2: -1
            ) else { return }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
        post(down: true)
        post(down: false)
    }
}
