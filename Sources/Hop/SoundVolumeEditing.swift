import HopCore

struct SoundVolumeEditing {
    private(set) var value: Double
    var text: String
    private var original: String
    private var cancelled = false

    init(value: Double) {
        self.value = value
        text = String(Int((value * 100).rounded()))
        original = text
    }

    mutating func begin() {
        text = String(Int((value * 100).rounded()))
        original = text
        cancelled = false
    }

    mutating func cancel() { cancelled = true }

    mutating func commit(maximum: Double) -> Double? {
        let parsed = !cancelled && text != original ? SoundPercentage.value(text, maximum: maximum * 100) : nil
        if let parsed { value = parsed }
        text = String(Int((value * 100).rounded()))
        return parsed
    }

    mutating func drag(to value: Double) {
        reflect(value)
        original = text
        cancelled = true
    }

    mutating func reflect(_ value: Double) {
        self.value = value
        text = String(Int((value * 100).rounded()))
    }
}
