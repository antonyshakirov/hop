import Foundation

@main
struct HopAudioWorker {
    @MainActor static func main() { if #available(macOS 14.2, *) { SoundInputWorker.run() } else { exit(1) } }
}
