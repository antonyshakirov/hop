import Foundation

@main
struct HopAudioWorker {
    @MainActor static func main() { SoundInputWorker.run() }
}
