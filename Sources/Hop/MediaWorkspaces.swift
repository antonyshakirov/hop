import Foundation

/// Each tool owns its queue and processing state; the panel module owns both.
@MainActor
final class MediaWorkspaces {
    let background = MediaController(operation: .background)
    let upscale = MediaController(operation: .upscale)

    var locked: Bool { background.locked || upscale.locked }

    func controller(for operation: MediaOperation) -> MediaController {
        operation == .background ? background : upscale
    }

    func cancel() {
        background.cancel()
        upscale.cancel()
    }
}

extension MediaOperation {
    var titleKey: L10nKey { self == .background ? .mediaRemove : .mediaUpscale }
}
