import Foundation

/// Keyboard events in; a layer effect and whether to swallow the event out.
/// Tests: Tests/HopCoreTests/HoldGestureTests.swift
public enum HoldGesture {
    public enum Phase: Equatable, Sendable {
        case idle
        case held
        /// Cancelled; waits until the chord is no longer fully held.
        case spent
    }

    public enum Input: Equatable, Sendable {
        case flagsChanged(keyCode: UInt16, flags: UInt64)
        case keyDown(UInt16, isRepeat: Bool)
        case keyUp(UInt16)
        /// A check outside the event stream found the chord not held: an event was lost.
        case chordNotHeld
    }

    public enum Effect: Equatable, Sendable {
        case none
        case begin
        case release
        case cancel
    }

    public struct State: Equatable, Sendable {
        public var phase: Phase
        public var modifiers: HoldModifiers
        public var swallowsChordKey: Bool

        public init() {
            phase = .idle
            modifiers = []
            swallowsChordKey = false
        }
    }

    public struct Step: Equatable, Sendable {
        public var state: State
        public var effect: Effect
        public var swallow: Bool

        public init(state: State, effect: Effect, swallow: Bool) {
            self.state = state
            self.effect = effect
            self.swallow = swallow
        }
    }

    public static func step(_ state: State, chord: HoldChord, input: Input) -> Step {
        var next = state
        switch input {
        case let .flagsChanged(keyCode, flags):
            next.modifiers = HoldModifiers.next(after: state.modifiers, keyCode: keyCode, flags: flags)
            let effect = modifiersChanged(&next, chord: chord)
            return Step(state: next, effect: effect, swallow: false)

        case let .keyDown(keyCode, isRepeat):
            if HoldModifiers.isModifierKey(keyCode) {
                return Step(state: next, effect: .none, swallow: false)
            }
            if keyCode == chord.keyCode, state.swallowsChordKey {
                if isRepeat {
                    return Step(state: next, effect: .none, swallow: true)
                }
                // SPEC: docs/spec.md — "Ink while a key is held": a fresh press means its key-up was lost.
                next.swallowsChordKey = false
            }
            switch next.phase {
            case .idle:
                if keyCode == chord.keyCode, !isRepeat, next.modifiers == chord.modifiers {
                    next.phase = .held
                    next.swallowsChordKey = true
                    return Step(state: next, effect: .begin, swallow: true)
                }
                return Step(state: next, effect: .none, swallow: false)
            case .held:
                next.phase = .spent
                return Step(state: next, effect: .cancel, swallow: false)
            case .spent:
                return Step(state: next, effect: .none, swallow: false)
            }

        case .chordNotHeld:
            return Step(state: State(), effect: state.phase == .held ? .release : .none, swallow: false)

        case let .keyUp(keyCode):
            guard keyCode == chord.keyCode, state.swallowsChordKey else {
                return Step(state: next, effect: .none, swallow: false)
            }
            next.swallowsChordKey = false
            if state.phase == .held {
                next.phase = .idle
                return Step(state: next, effect: .release, swallow: true)
            }
            return Step(state: next, effect: .none, swallow: true)
        }
    }

    private static func modifiersChanged(_ state: inout State, chord: HoldChord) -> Effect {
        let held = state.modifiers
        let wanted = chord.modifiers
        switch state.phase {
        case .idle:
            if chord.keyCode == nil, held == wanted {
                state.phase = .held
                return .begin
            }
            return .none
        case .held:
            if !held.isSubset(of: wanted) {
                state.phase = .spent
                return .cancel
            }
            if held != wanted {
                state.phase = .idle
                return .release
            }
            return .none
        case .spent:
            if !held.isSuperset(of: wanted) {
                state.phase = .idle
            }
            return .none
        }
    }
}

/// Records a chord from raw key events; after recording or cancelling, every call waits.
/// Tests: Tests/HopCoreTests/HoldGestureTests.swift
public struct HoldRecorder: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        case waiting
        case recorded(HoldChord)
        case cancelled
    }

    private var current: HoldModifiers = []
    private var peak: HoldModifiers = []
    private var finished = false

    public init() {}

    public mutating func flagsChanged(keyCode: UInt16, flags: UInt64) -> Outcome {
        guard !finished else { return .waiting }
        current = HoldModifiers.next(after: current, keyCode: keyCode, flags: flags)
        peak.formUnion(current)
        guard current.isEmpty else { return .waiting }
        let chord = HoldChord(modifiers: peak)
        peak = []
        guard chord.isValid else { return .waiting }
        finished = true
        return .recorded(chord)
    }

    public mutating func keyDown(_ keyCode: UInt16) -> Outcome {
        guard !finished else { return .waiting }
        if keyCode == 53 {
            finished = true
            return .cancelled
        }
        guard !HoldModifiers.isModifierKey(keyCode), !current.isEmpty else { return .waiting }
        let chord = HoldChord(modifiers: current, keyCode: keyCode)
        guard chord.isValid else { return .waiting }
        finished = true
        return .recorded(chord)
    }
}
