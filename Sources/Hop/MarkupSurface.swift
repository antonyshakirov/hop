import AppKit
import HopCore
import SwiftUI

/// The state one markup surface carries: the marks, the tool in hand, the ink
/// each tool remembers, and the clock fading ink measures itself by.
///
/// The tick runs ONLY while something is fading — a layer of ordinary marks
/// keeps no schedule alive.
/// SPEC: .claude/specs/2026-09-07-markup-modules-design.md
@MainActor
final class MarkupSurface: ObservableObject {
    @Published private(set) var shapes: [MarkupShape] = []
    @Published private(set) var drafting: MarkupShape?
    /// SPEC: docs/spec.md — another tool ends the edit in progress.
    @Published var tool: MarkupTool = .pencil {
        didSet { if tool != oldValue, tool != .select { letGo() } }
    }
    /// The pointer is over a panel rather than over the picture. A nib drawn
    /// over the toolbar is a nib nobody can press a button with.
    @Published var pointerOverPanel = false
    @Published var blur = MarkupBlur(mode: .inside, shape: .rectangle, style: .blur, strength: 5, dim: 2)
    /// The head the arrow tool draws, remembered between sessions.
    @Published var arrowStyle: ArrowStyle = MarkupSettings.arrowStyle() {
        didSet { MarkupSettings.store(arrowStyle: arrowStyle) }
    }
    @Published private(set) var now: TimeInterval = 0
    /// A text mark waiting for its words; the canvas shows a field over it.
    @Published var typing: MarkupShape?
    /// The mark in hand, while the select tool has hold of it.
    @Published private(set) var selection: UUID?
    /// That mark as it is being moved or pulled about. It stands in for the
    /// stored one until the drag ends, so the whole edit is ONE undo step.
    @Published private(set) var editing: MarkupShape?

    private let document = MarkupDocument()
    private var book = MarkupInkBook(inks: MarkupSettings.inks(),
                                     shared: MarkupSettings.sharedColour(),
                                     common: MarkupSettings.commonColour())
    private var origin: MarkupPoint?
    /// SPEC: docs/spec.md — each monitor keeps its own marks.
    private var display: UInt32?
    private var grip: Int?
    private var grabbed: MarkupPoint?
    private var turningDial = false
    /// The button is down. A tool that acts on the PRESS rather than on a drag
    /// must act once, not once per step of a hand that is merely holding still.
    private var pressed = false
    private var ticker: Timer?
    private let opened = Date()

    /// The setting lives in the settings window, the colours live here: the
    /// switch is heard rather than read, so a colour shared while the editor is
    /// open spreads at once.
    init() {
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.matchColourSetting() }
        }
    }

    var canUndo: Bool { document.canUndo }
    var canRedo: Bool { document.canRedo }

    /// Marks that are still worth drawing at this instant.
    var visible: [MarkupShape] {
        // A caption being typed is drawn by its field, not by the canvas, or it
        // shows twice.
        var living = FadingInk.alive(shapes, now: now).filter { $0.id != typing?.id }
        if let editing {
            living = living.map { $0.id == editing.id ? editing : $0 }
        }
        guard let drafting else { return living }
        return living + [drafting]
    }

    func visible(on display: UInt32?) -> [MarkupShape] {
        MarkupScreens.on(display, visible)
    }

    /// Something is under the hand: a mark being drawn, or one being moved.
    var isDragging: Bool { pressed || drafting != nil || editing != nil }

    /// The mark the handles belong to, as it looks right now.
    var selected: MarkupShape? {
        guard let selection else { return nil }
        if let editing, editing.id == selection { return editing }
        return shapes.first { $0.id == selection }
    }

    private func letGo() {
        commitTyping()
        selection = nil
        editing = nil
        grip = nil
        grabbed = nil
        turningDial = false
        dropTheKeyboard()
    }

    /// WORKAROUND: `NSApp` is implicitly unwrapped and nil in the headless
    /// self-test, where nothing holds the keyboard anyway.
    private func dropTheKeyboard() {
        guard NSApp != nil else { return }
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    @discardableResult
    func deleteSelection() -> Bool {
        guard let selection else { return false }
        document.apply { StepNumbering.renumbered($0.filter { $0.id != selection }) }
        self.selection = nil
        editing = nil
        publish()
        return true
    }

    /// How near the pointer has to be to take hold of a handle, in the picture's
    /// own points.
    static let gripReach: Double = 9

    private func handle(of shape: MarkupShape, near point: MarkupPoint) -> Int? {
        let spots = MarkupEditing.handles(of: shape)
        for (index, spot) in spots.enumerated() {
            let dx = spot.x - point.x, dy = spot.y - point.y
            if (dx * dx + dy * dy).squareRoot() <= Self.gripReach { return index }
        }
        return nil
    }

    private func pick(at point: MarkupPoint) {
        // The dial and the handles of the mark already in hand win over
        // anything under them.
        let current = selected.flatMap { MarkupScreens.belongs($0, to: display) ? $0 : nil }
        if let current, current.tool == .magnifier,
           let knob = MarkupEditing.Zoom.knob(of: current),
           near(knob, point) {
            turningDial = true
            editing = current
            return
        }
        if let current, let index = handle(of: current, near: point) {
            grip = index
            turningDial = false
            editing = current
            return
        }
        guard let hit = MarkupScreens.on(display, FadingInk.alive(shapes, now: now))
            .last(where: { MarkupEditing.grabbed($0, at: point, tolerance: 8) })
        else {
            selection = nil
            editing = nil
            grabbed = nil
            return
        }
        selection = hit.id
        editing = hit
        grip = nil
        turningDial = false
        grabbed = point
    }

    private func near(_ spot: MarkupPoint, _ point: MarkupPoint) -> Bool {
        let dx = spot.x - point.x, dy = spot.y - point.y
        return (dx * dx + dy * dy).squareRoot() <= Self.gripReach
    }

    /// What is still on the surface right now, read off the clock rather than
    /// the tick: ink that has faded from the screen must not turn up in a file.
    var lasting: [MarkupShape] {
        FadingInk.alive(shapes, now: Date().timeIntervalSince(opened))
    }

    func ink(for tool: MarkupTool) -> MarkupInk {
        book.ink(for: tool, standard: Self.standardInk)
    }

    func setInk(_ ink: MarkupInk, for tool: MarkupTool) {
        book.set(ink, for: tool, standard: Self.standardInk)
        rememberInks()
        // A mark in hand is what the user is looking at: colour and width go on
        // IT, not only on the next mark of that kind.
        if let held = selected, held.ink != ink {
            var edited = held
            edited.ink = ink
            document.update(edited)
            publish()
        }
        objectWillChange.send()
    }

    /// A switch thrown in the settings window while this surface is open.
    private func matchColourSetting() {
        let wanted = MarkupSettings.sharedColour()
        guard wanted != book.shared else { return }
        book.share(wanted, from: tool, standard: Self.standardInk)
        rememberInks()
        objectWillChange.send()
    }

    private func rememberInks() {
        MarkupSettings.store(inks: book.stored)
        MarkupSettings.store(commonColour: book.commonColour)
    }

    /// The blur being set right now: the selected blur mark's own settings, or
    /// the template the next one will be drawn with.
    var blurInHand: MarkupBlur {
        get {
            if let held = selected, held.tool == .blur, let its = held.blur { return its }
            return blur
        }
        set {
            blur = newValue
            guard let held = selected, held.tool == .blur else { return }
            var edited = held
            edited.blur = newValue
            document.update(edited)
            publish()
        }
    }

    func opacity(of shape: MarkupShape) -> Double {
        // A stroke still under the hand keeps its full strength: the countdown
        // belongs to the lift, not to the first point.
        guard shape.id != drafting?.id else { return 1 }
        return FadingInk.opacity(of: shape, now: now)
    }

    func begin(at point: MarkupPoint, on display: UInt32? = nil) {
        pressed = true
        self.display = display
        let stamp = Date().timeIntervalSince(opened)
        switch tool {
        case .select:
            pick(at: point)
        case .eraser:
            erase(at: point)
        case .steps:
            let circle = MarkupShape(tool: .steps, points: [point], ink: ink(for: .steps),
                                     step: StepNumbering.next(in: MarkupScreens.on(display, shapes)),
                                     display: display, createdAt: stamp)
            document.add(circle)
            publish()
        case .text:
            commitTyping()
            // A caption already there is EDITED, not written over: clicking one
            // to start a second on top of it is nobody's intention.
            if let held = MarkupScreens.on(display, FadingInk.alive(shapes, now: now)).last(where: {
                $0.tool == .text && MarkupEditing.grabbed($0, at: point, tolerance: 8)
            }) {
                typing = held
                selection = held.id
                publish()
                return
            }
            typing = MarkupShape(tool: .text, points: [point], ink: ink(for: .text),
                                 text: "", display: display, createdAt: stamp)
        default:
            origin = point
            var shape = MarkupShape(tool: tool, points: [point], ink: ink(for: tool),
                                    display: display, createdAt: stamp)
            if tool == .blur { shape.blur = blur }
            if tool == .arrow { shape.arrow = arrowStyle }
            drafting = shape
        }
    }

    func extend(to point: MarkupPoint, modifiers: MarkupDrag.Modifiers = .none) {
        // The rubber goes on rubbing for as long as it is held; the numbered
        // circles and the caption are placed once per press.
        if tool == .eraser {
            erase(at: point)
            return
        }
        if tool == .select {
            guard var held = editing else { return }
            if turningDial, let lens = MarkupEditing.lens(of: held) {
                held.magnification = MarkupEditing.Zoom.asked(at: point, lens: lens)
                editing = held
                return
            }
            if let grip {
                held = MarkupEditing.pulled(held, handle: grip, to: point)
            } else if let grabbed {
                held = MarkupEditing.moved(held, by: MarkupPoint(x: point.x - grabbed.x,
                                                                 y: point.y - grabbed.y))
                self.grabbed = point
            }
            editing = held
            return
        }
        guard var shape = drafting else { return }
        switch shape.tool {
        case .pencil, .fadingInk, .marker:
            // A held shift turns the stroke into one straight run from where it
            // began, on the nearest of eight bearings. Let go and it goes on
            // following the hand from there.
            if modifiers.regular, let origin {
                shape.points = MarkupDrag.points(tool: .line, origin: origin,
                                                 current: point,
                                                 modifiers: .init(regular: true))
            } else if let last = shape.points.last,
                      MarkupGeometry.worthAdding(point, after: last) {
                shape.points.append(point)
            } else if shape.points.isEmpty {
                shape.points.append(point)
            }
        default:
            shape.points = MarkupDrag.points(tool: shape.tool, origin: origin ?? point,
                                             current: point, modifiers: modifiers)
        }
        drafting = shape
    }

    /// Where the mark in hand began, while it is still being drawn.
    var anchor: MarkupPoint? {
        guard let drafting else { return nil }
        switch drafting.tool {
        case .pencil, .fadingInk, .marker, .eraser: return nil
        default: return origin
        }
    }

    func finish() {
        pressed = false
        if tool == .select {
            defer { grip = nil; grabbed = nil; turningDial = false }
            guard let held = editing else { return }
            editing = nil
            guard held != shapes.first(where: { $0.id == held.id }) else { return }
            document.update(held)
            publish()
            return
        }
        defer { origin = nil }
        guard var shape = drafting else { return }
        drafting = nil
        guard shape.points.count > 1 else { return }
        // Fading ink counts from the moment the pointer LIFTS, not from the
        // moment the stroke began: a long line was half gone before it was
        // finished (Anton, 2026-09-09). SPEC: docs/spec.md — fading ink.
        if shape.tool == .fadingInk {
            shape.createdAt = Date().timeIntervalSince(opened)
        }
        document.add(shape)
        // A blur is not finished when it is drawn: what it does is set on it
        // afterwards, so it comes out of the drag already in hand.
        if shape.tool == .blur {
            selection = shape.id
            tool = .select
        }
        publish()
    }

    /// The words are kept only when there are some: an empty label would be an
    /// invisible mark nobody can select again.
    func commitTyping() {
        guard var shape = typing else { return }
        typing = nil
        // The field editor keeps the keyboard until it is told otherwise, and
        // backspace over a selected mark went into a field nobody could see.
        dropTheKeyboard()
        shape.text = shape.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let known = shapes.contains { $0.id == shape.id }
        guard let text = shape.text, !text.isEmpty else {
            // Emptied, it goes: a caption with no words is an invisible mark
            // nobody can select again.
            if known {
                document.apply { $0.filter { $0.id != shape.id } }
                publish()
            }
            return
        }
        if known { document.update(shape) } else { document.add(shape) }
        publish()
    }

    func erase(at point: MarkupPoint) {
        guard let hit = MarkupScreens.on(display, shapes)
            .last(where: { MarkupGeometry.hits(shape: $0, point: point, tolerance: 6) })
        else { return }
        document.apply { StepNumbering.renumbered($0.filter { $0.id != hit.id }) }
        publish()
    }

    /// A lens is PUT DOWN, not drawn out: it lands whole in the middle of the
    /// picture and is moved, resized and deleted like any other mark.
    /// SPEC: docs/spec.md
    func placeLens(centre: MarkupPoint, side: Double) {
        let half = side / 2
        let lens = MarkupShape(
            tool: .magnifier,
            points: [MarkupPoint(x: centre.x - half, y: centre.y - half),
                     MarkupPoint(x: centre.x + half, y: centre.y + half)],
            ink: ink(for: .magnifier),
            createdAt: Date().timeIntervalSince(opened)
        )
        document.add(lens)
        selection = lens.id
        editing = nil
        tool = .select
        publish()
    }

    /// Marks put on the surface wholesale. SPEC: the canvas self-test.
    func load(_ marks: [MarkupShape]) {
        document.apply { _ in marks }
        publish()
    }

    func undo() {
        document.undo()
        publish()
    }

    func redo() {
        document.redo()
        publish()
    }

    func clear() {
        document.clear()
        publish()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
    }

    private func publish() {
        shapes = document.shapes
        now = Date().timeIntervalSince(opened)
        keepTimeIfAnythingFades()
    }

    private func keepTimeIfAnythingFades() {
        let needed = FadingInk.needsTicking(shapes, now: now)
        if needed, ticker == nil {
            ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.now = Date().timeIntervalSince(self.opened)
                    if !FadingInk.needsTicking(self.shapes, now: self.now) {
                        self.shapes = FadingInk.alive(self.shapes, now: self.now)
                        self.stop()
                    }
                }
            }
        } else if !needed {
            stop()
        }
    }

    private static func standardInk(for tool: MarkupTool) -> MarkupInk {
        switch tool {
        case .marker: return MarkupInk(hex: "#FFD60A", width: 18)
        case .fadingInk: return MarkupInk(hex: "#FF453A", width: 5)
        case .text: return MarkupInk(hex: "#FF453A", width: 18)
        case .steps: return MarkupInk(hex: "#FF453A", width: 2)
        case .select: return MarkupInk(hex: "#FF453A", width: 4)
        default: return MarkupInk(hex: "#FF453A", width: 4)
        }
    }
}

extension Color {
    /// The nearest sRGB hex, for a colour chosen in the system picker.
    var markupHex: String {
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return "#FF453A" }
        return ColorFormatting.hex(r: Int((srgb.redComponent * 255).rounded()),
                                   g: Int((srgb.greenComponent * 255).rounded()),
                                   b: Int((srgb.blueComponent * 255).rounded()))
    }

    init(markupHex: String) {
        guard let parts = ColorFormatting.components(markupHex) else {
            self = .red
            return
        }
        self = Color(red: Double(parts.r) / 255, green: Double(parts.g) / 255, blue: Double(parts.b) / 255)
    }
}
