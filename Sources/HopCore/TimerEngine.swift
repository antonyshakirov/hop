import Foundation

/// Timer core. Counts from a target date instead of decrementing,
/// so it never drifts and survives Mac sleep.
public final class TimerEngine: ObservableObject {
    public enum State: Equatable {
        case idle
        case running
        case paused
        case finished
    }

    /// Active timer set aside in the stash — appears when a preset
    /// is picked during a countdown.
    public struct Stash: Equatable {
        public let remaining: TimeInterval
        public let duration: TimeInterval
    }

    /// Current phase of the work-rest cycle.
    public struct CycleState: Equatable {
        public let isWork: Bool
        public let round: Int
        public let rounds: Int
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var duration: TimeInterval
    @Published public private(set) var stash: Stash?
    @Published public private(set) var cycle: CycleState?
    /// Stopwatch mode: time grows from zero; presets/scrubbing don't apply.
    @Published public private(set) var isStopwatch = false
    /// Updated by the ticker every 0.25 s while the timer runs or the finish blinks — drives the UI.
    @Published public private(set) var heartbeat: Date

    public var onFinish: (() -> Void)?
    /// Fired between cycle phases (the next phase starts on its own).
    public var onPhaseChange: ((_ nextIsWork: Bool) -> Void)?

    private var stopwatchStartRef: Date?
    private var stopwatchAccumulated: TimeInterval = 0

    private var phaseQueue: [(isWork: Bool, duration: TimeInterval)] = []
    private var totalRounds = 0
    private var currentRound = 0

    // zero is allowed: seconds are set digit by digit (0:00:01 is valid),
    // and play with an all-zero value just finishes instantly
    public static let minimumDuration: TimeInterval = 0
    public static let step: TimeInterval = 5 * 60

    // @Published so that on-the-fly time edits reach the UI instantly,
    // without waiting for the ticker.
    @Published private var targetDate: Date?
    @Published private var pausedRemaining: TimeInterval?
    private let now: () -> Date
    private var ticker: Timer?

    public init(duration: TimeInterval = 10 * 60, now: @escaping () -> Date = Date.init) {
        self.duration = duration
        self.now = now
        self.heartbeat = now()
    }

    public var remaining: TimeInterval {
        switch state {
        case .idle:
            return duration
        case .running:
            guard let targetDate else { return 0 }
            return max(0, targetDate.timeIntervalSince(now()))
        case .paused:
            return pausedRemaining ?? duration
        case .finished:
            return 0
        }
    }

    /// Elapsed stopwatch time.
    public var elapsed: TimeInterval {
        guard isStopwatch else { return 0 }
        if state == .running, let ref = stopwatchStartRef {
            return stopwatchAccumulated + now().timeIntervalSince(ref)
        }
        return stopwatchAccumulated
    }

    /// Switch timer ↔ stopwatch (while at rest).
    public func setStopwatch(_ on: Bool) {
        // switching from pause IS allowed: pause means "already stopped", and the
        // mode change deliberately abandons the unfinished timer. Only running is off-limits
        guard state != .running else { return }
        clearCycle()
        stash = nil
        stopTicker()
        isStopwatch = on
        stopwatchAccumulated = 0
        stopwatchStartRef = nil
        targetDate = nil
        pausedRemaining = nil
        state = .idle
        heartbeat = now()
    }

    private func exitStopwatch() {
        isStopwatch = false
        stopwatchAccumulated = 0
        stopwatchStartRef = nil
    }

    /// Prepare the work-rest cycle: the queue is built, the display shows
    /// the first phase, and start happens via the regular play button.
    public func prepareCycle(work: TimeInterval, rest: TimeInterval, rounds: Int) {
        guard state == .idle || state == .finished else { return }
        exitStopwatch()
        stash = nil
        stopTicker()
        phaseQueue = []
        let count = max(1, rounds)
        for index in 0..<count {
            phaseQueue.append((true, max(1, work)))
            if index < count - 1, rest > 0 {
                phaseQueue.append((false, rest))
            }
        }
        totalRounds = count
        currentRound = 0
        duration = max(1, work)
        state = .idle
        cycle = CycleState(isWork: true, round: 1, rounds: count) // "armed"
    }

    /// Start the cycle immediately (used in tests/automation).
    public func startCycle(work: TimeInterval, rest: TimeInterval, rounds: Int) {
        prepareCycle(work: work, rest: rest, rounds: rounds)
        startNextPhase()
    }

    private func startNextPhase() {
        guard !phaseQueue.isEmpty else {
            cycle = nil
            return
        }
        let phase = phaseQueue.removeFirst()
        if phase.isWork { currentRound += 1 }
        cycle = CycleState(isWork: phase.isWork, round: currentRound, rounds: totalRounds)
        duration = phase.duration
        targetDate = now().addingTimeInterval(phase.duration)
        pausedRemaining = nil
        state = .running
        startTicker()
    }

    private func clearCycle() {
        phaseQueue = []
        cycle = nil
        totalRounds = 0
        currentRound = 0
    }

    /// Set the duration directly (scrubbing on the display). Works in idle/finished.
    public func setDuration(_ seconds: TimeInterval) {
        guard !isStopwatch else { return }
        guard state == .idle || state == .finished else { return }
        if state == .finished {
            stopTicker()
            state = .idle
        }
        duration = max(Self.minimumDuration, seconds)
    }

    public func setPreset(minutes: Int) {
        exitStopwatch()
        clearCycle()
        if state == .running || state == .paused {
            stash = Stash(remaining: remaining, duration: duration)
        }
        stopTicker()
        duration = TimeInterval(minutes * 60)
        targetDate = nil
        pausedRemaining = nil
        state = .idle
    }

    /// Return to the last active timer: resumes the countdown from where
    /// the preset selection interrupted it.
    public func restoreStash() {
        guard let s = stash else { return }
        stash = nil
        duration = s.duration
        pausedRemaining = nil
        targetDate = now().addingTimeInterval(s.remaining)
        state = .running
        startTicker()
    }

    public func adjust(by delta: TimeInterval) {
        switch state {
        case .idle:
            duration = max(Self.minimumDuration, duration + delta)
        case .finished:
            stopTicker()
            duration = max(Self.minimumDuration, duration + delta)
            state = .idle
        case .running:
            targetDate = (targetDate ?? now()).addingTimeInterval(delta)
            if remaining <= 0 { finish() }
        case .paused:
            pausedRemaining = max(0, (pausedRemaining ?? duration) + delta)
            if (pausedRemaining ?? 0) <= 0 { finish() }
        }
    }

    public func toggle() {
        switch state {
        case .idle, .finished: start()
        case .running: pause()
        case .paused: resume()
        }
    }

    public func start() {
        if isStopwatch {
            stopwatchStartRef = now()
            state = .running
            startTicker()
            return
        }
        if !phaseQueue.isEmpty, state == .idle || state == .finished {
            // armed cycle: play starts the first phase
            startNextPhase()
            return
        }
        // the stash only protects against an accidental preset click:
        // deliberately starting a new timer cancels the old one
        stash = nil
        clearCycle()
        guard duration > 0 else {
            // everything is zero — nothing to run, finish right away
            finish()
            return
        }
        targetDate = now().addingTimeInterval(duration)
        pausedRemaining = nil
        state = .running
        startTicker()
    }

    public func pause() {
        guard state == .running else { return }
        if isStopwatch {
            stopwatchAccumulated = elapsed
            stopwatchStartRef = nil
            state = .paused
            stopTicker()
            return
        }
        pausedRemaining = remaining
        targetDate = nil
        state = .paused
        stopTicker()
    }

    public func resume() {
        guard state == .paused else { return }
        if isStopwatch {
            stopwatchStartRef = now()
            state = .running
            startTicker()
            return
        }
        targetDate = now().addingTimeInterval(pausedRemaining ?? duration)
        pausedRemaining = nil
        state = .running
        startTicker()
    }

    public func reset() {
        clearCycle()
        stopwatchAccumulated = 0
        stopwatchStartRef = nil
        stopTicker()
        targetDate = nil
        pausedRemaining = nil
        state = .idle
        heartbeat = now()
    }

    /// Called by the ticker; invoked manually in tests.
    public func tick() {
        heartbeat = now()
        if !isStopwatch, state == .running, remaining <= 0 { finish() }
    }

    private func finish() {
        if !phaseQueue.isEmpty {
            // between cycle phases: sound the cue and start the next phase right away
            let nextIsWork = phaseQueue.first?.isWork ?? true
            onPhaseChange?(nextIsWork)
            startNextPhase()
            return
        }
        cycle = nil
        targetDate = nil
        pausedRemaining = nil
        state = .finished
        onFinish?()
        startTicker() // the ticker keeps running for the blinking
    }

    private func startTicker() {
        stopTicker()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}
