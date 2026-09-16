import AppKit
import Combine
import HopCore
import os

/// Ink while a chord is held: owns the event tap and the ink layer.
/// SPEC: docs/spec.md — "Ink while a key is held".
@MainActor
final class HoldDrawController {
    var suspended = false {
        didSet { reconcile() }
    }

    /// True while the gesture is wanted but no tap could be installed; the settings show the access line.
    private(set) var tapFailed = false

    private let isFullLayerUp: () -> Bool
    private let isKeyboardLocked: () -> Bool
    private let layer = HoldInkLayer()
    private var tap: HoldTap?
    private var trusted = AXIsProcessTrusted()
    private var lastInputs: Inputs?
    private var observers: [NSObjectProtocol] = []
    private var alertWatch: AnyCancellable?

    private struct Inputs: Equatable {
        var holdOn: Bool
        var chord: String
        var moduleOn: Bool
        var suspended: Bool
        var fullLayerUp: Bool
        var locked: Bool
        var trusted: Bool
    }

    init(isFullLayerUp: @escaping () -> Bool, isKeyboardLocked: @escaping () -> Bool) {
        self.isFullLayerUp = isFullLayerUp
        self.isKeyboardLocked = isKeyboardLocked

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: ModuleActivation.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        })
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.recheckTrust() }
        })
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated { self?.recheckTrust() }
            }
        })
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tap?.resetGesture() }
        })
        alertWatch = AccessibilityWatch.shared.$alert
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.recheckTrust() }
            }
        reconcile()
    }

    func reconcile() {
        let chord = MarkupSettings.holdChord()
        let inputs = Inputs(
            holdOn: MarkupSettings.holdOn(),
            chord: chord.storage,
            moduleOn: ModuleActivation.isOn("annotate"),
            suspended: suspended,
            fullLayerUp: isFullLayerUp(),
            locked: isKeyboardLocked(),
            trusted: trusted)
        guard inputs != lastInputs else { return }
        let chordChanged = inputs.chord != lastInputs?.chord
        lastInputs = inputs

        let wanted = !Snapshot.active && inputs.moduleOn && inputs.holdOn && inputs.trusted
            && chord.isValid && !inputs.suspended && !inputs.fullLayerUp && !inputs.locked
        guard wanted else {
            tap?.remove()
            tap = nil
            tapFailed = false
            layer.dismiss()
            return
        }
        if let tap {
            if chordChanged {
                tap.use(chord)
                layer.dismiss()
            }
            return
        }
        tap = HoldTap.install(chord: chord) { [weak self] effect in
            MainActor.assumeIsolated { self?.apply(effect) }
        } onLostTrust: { [weak self] in
            MainActor.assumeIsolated { self?.recheckTrust() }
        }
        tapFailed = tap == nil
        if tapFailed { lastInputs = nil }
    }

    private func recheckTrust() {
        trusted = AXIsProcessTrusted()
        reconcile()
    }

    private func apply(_ effect: HoldGesture.Effect) {
        switch effect {
        case .none:
            break
        case .begin:
            guard !isFullLayerUp(), !isKeyboardLocked() else { return }
            layer.show(ink: MarkupSettings.holdInk())
        case .release:
            if layer.isShowing { layer.fadeAway() }
        case .cancel:
            layer.dismiss()
        }
    }
}

/// The event tap on its own thread, so filtering keys never waits on Hop's main thread.
/// SPEC: docs/spec.md — "Ink while a key is held", the cost rule.
private final class HoldTap: @unchecked Sendable {
    private struct Shared {
        var chord: HoldChord
        var state = HoldGesture.State()
        var port: CFMachPort?
        var removed = false
    }

    private let shared: OSAllocatedUnfairLock<Shared>
    private let onEffect: @Sendable (HoldGesture.Effect) -> Void
    private let onLostTrust: @Sendable () -> Void
    private var runLoop: CFRunLoop?

    private init(chord: HoldChord,
                 onEffect: @escaping @Sendable (HoldGesture.Effect) -> Void,
                 onLostTrust: @escaping @Sendable () -> Void) {
        shared = OSAllocatedUnfairLock(initialState: Shared(chord: chord))
        self.onEffect = onEffect
        self.onLostTrust = onLostTrust
    }

    static func install(chord: HoldChord,
                        onEffect: @escaping @Sendable (HoldGesture.Effect) -> Void,
                        onLostTrust: @escaping @Sendable () -> Void) -> HoldTap? {
        let box = HoldTap(chord: chord, onEffect: onEffect, onLostTrust: onLostTrust)
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: holdTapCallback,
            userInfo: Unmanaged.passUnretained(box).toOpaque()
        ) else { return nil }
        box.shared.withLock { $0.port = port }

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [box] in
            guard let source = CFMachPortCreateRunLoopSource(nil, port, 0) else {
                ready.signal()
                return
            }
            let loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(loop, source, .commonModes)
            box.runLoop = loop
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "hop.hold-to-draw"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        guard box.runLoop != nil else {
            CFMachPortInvalidate(port)
            return nil
        }
        return box
    }

    func use(_ chord: HoldChord) {
        shared.withLock {
            $0.chord = chord
            $0.state = HoldGesture.State()
        }
    }

    func remove() {
        let port = shared.withLock { shared -> CFMachPort? in
            shared.removed = true
            defer { shared.port = nil }
            return shared.port
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let runLoop {
            CFRunLoopStop(runLoop)
        }
    }

    func resetGesture() {
        shared.withLock { $0.state = HoldGesture.State() }
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let input: HoldGesture.Input
        switch type {
        case .flagsChanged:
            input = .flagsChanged(
                keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
                flags: event.flags.rawValue)
        case .keyDown:
            input = .keyDown(
                UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        case .keyUp:
            input = .keyUp(UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)))
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            let port = shared.withLock { shared -> CFMachPort? in
                shared.state = HoldGesture.State()
                return shared.removed ? nil : shared.port
            }
            let notify = onEffect
            DispatchQueue.main.async { notify(.cancel) }
            if AXIsProcessTrusted() {
                if let port { CGEvent.tapEnable(tap: port, enable: true) }
            } else {
                let lost = onLostTrust
                DispatchQueue.main.async { lost() }
            }
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }

        let step = shared.withLock { shared -> HoldGesture.Step in
            let step = HoldGesture.step(shared.state, chord: shared.chord, input: input)
            shared.state = step.state
            return step
        }
        if step.effect != .none {
            let notify = onEffect
            let effect = step.effect
            DispatchQueue.main.async { notify(effect) }
        }
        return step.swallow ? nil : Unmanaged.passUnretained(event)
    }
}

private func holdTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<HoldTap>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.handle(type: type, event: event)
}
