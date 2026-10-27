import AVFoundation
import OSLog

/// A Bluetooth input can renegotiate while its first tap is being installed.
public enum SoundMicrophoneTapStartup {
    private static let log = Logger(subsystem: "com.antonshakirov.hop", category: "HopMix")

    public static func start(readFormat: () -> AVAudioFormat, installTap: () -> Void,
                             removeTap: () -> Void, stop: () -> Void,
                             start: () throws -> Void) throws {
        let initial = readFormat()
        guard valid(initial) else {
            stop()
            throw NSError(domain: NSOSStatusErrorDomain, code: -10868)
        }
        installTap()
        do { try start() }
        catch {
            removeTap(); stop()
            let failure = error as NSError
            guard failure.code == -10868,
                  [NSOSStatusErrorDomain, "com.apple.coreaudio.avfaudio"].contains(failure.domain)
            else { throw error }
            let negotiated = readFormat()
            guard valid(negotiated), !initial.isEqual(negotiated) else { throw error }
            log.notice("microphone-format-negotiated oldRate=\(initial.sampleRate, privacy: .public) newRate=\(negotiated.sampleRate, privacy: .public); reinstalling-tap")
            // Keep format:nil at the call site: an explicit cached format can
            // raise an Objective-C exception if the hardware changes again.
            installTap()
            do { try start() }
            catch { removeTap(); stop(); throw error }
        }
    }

    private static func valid(_ format: AVAudioFormat) -> Bool {
        format.sampleRate.isFinite && format.sampleRate >= 8000 && format.channelCount > 0
    }
}
