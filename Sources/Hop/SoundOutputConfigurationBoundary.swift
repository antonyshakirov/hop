final class SoundOutputConfigurationBoundary {
    private var initialized = false
    private var outputUID: String?
    private var masterUID: String?

    func transition(outputUID: String?, masterUID: String?,
                    playback: () -> (identity: ObjectIdentifier?, uid: String?, active: Bool),
                    gate: () -> Void, update: () throws -> Void, activate: () throws -> Void) rethrows {
        let previous = playback()
        var gated = false
        try apply(outputUID: outputUID, masterUID: masterUID, gate: {
            gated = true; gate()
        }, update: update)
        let current = playback()
        if gated, previous.active, current.active, previous.uid == outputUID,
           previous.identity != nil, previous.identity == current.identity { try activate() }
    }

    func apply(outputUID: String?, masterUID: String?, gate: () -> Void, update: () throws -> Void) rethrows {
        // SPEC: docs/spec.md — "Mac volume across listening destinations".
        if initialized && (self.outputUID != outputUID || self.masterUID != masterUID) { gate() }
        try update()
        self.outputUID = outputUID; self.masterUID = masterUID; initialized = true
    }
}
