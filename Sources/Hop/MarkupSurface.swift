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
    @Published var tool: MarkupTool = .pencil
    @Published var blur = MarkupBlur(mode: .inside, shape: .rectangle, style: .blur, strength: 7, dim: 2)
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
    private var inks: [MarkupTool: MarkupInk] = MarkupSettings.inks()
    private var origin: MarkupPoint?
    private var grip: Int?
    private var grabbed: MarkupPoint?
    private var ticker: Timer?
    private let opened = Date()

    var canUndo: Bool { document.canUndo }
    var canRedo: Bool { document.canRedo }

    /// Marks that are still worth drawing at this instant.
    var visible: [MarkupShape] {
        var living = FadingInk.alive(shapes, now: now)
        if let editing {
            living = living.map { $0.id == editing.id ? editing : $0 }
        }
        guard let drafting else { return living }
        return living + [drafting]
    }

    /// The mark the handles belong to, as it looks right now.
    var selected: MarkupShape? {
        guard let selection else { return nil }
        if let editing, editing.id == selection { return editing }
        return shapes.first { $0.id == selection }
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
        // A handle of the mark already in hand wins over anything under it.
        if let current = selected, let index = handle(of: current, near: point) {
            grip = index
            editing = current
            return
        }
        guard let hit = FadingInk.alive(shapes, now: now)
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
        grabbed = point
    }

    /// What is still on the surface right now, read off the clock rather than
    /// the tick: ink that has faded from the screen must not turn up in a file.
    var lasting: [MarkupShape] {
        FadingInk.alive(shapes, now: Date().timeIntervalSince(opened))
    }

    func ink(for tool: MarkupTool) -> MarkupInk {
        inks[tool] ?? Self.standardInk(for: tool)
    }

    func setInk(_ ink: MarkupInk, for tool: MarkupTool) {
        inks[tool] = ink
        MarkupSettings.store(inks: inks)
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
        FadingInk.opacity(of: shape, now: now)
    }

    func begin(at point: MarkupPoint) {
        let stamp = Date().timeIntervalSince(opened)
        switch tool {
        case .select:
            pick(at: point)
        case .eraser:
            erase(at: point)
        case .steps:
            let circle = MarkupShape(tool: .steps, points: [point], ink: ink(for: .steps),
                                     step: StepNumbering.next(in: shapes), createdAt: stamp)
            document.add(circle)
            publish()
        case .text:
            commitTyping()
            typing = MarkupShape(tool: .text, points: [point], ink: ink(for: .text),
                                 text: "", createdAt: stamp)
        default:
            origin = point
            var shape = MarkupShape(tool: tool, points: [point], ink: ink(for: tool), createdAt: stamp)
            if tool == .blur { shape.blur = blur }
            if tool == .arrow { shape.arrow = arrowStyle }
            drafting = shape
        }
    }

    func extend(to point: MarkupPoint, modifiers: MarkupDrag.Modifiers = .none) {
        if tool == .select {
            guard var held = editing else { return }
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
            } else {
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
        if tool == .select {
            defer { grip = nil; grabbed = nil }
            guard let held = editing else { return }
            editing = nil
            guard held != shapes.first(where: { $0.id == held.id }) else { return }
            document.update(held)
            publish()
            return
        }
        defer { origin = nil }
        guard let shape = drafting else { return }
        drafting = nil
        guard shape.points.count > 1 else { return }
        document.add(shape)
        publish()
    }

    /// The words are kept only when there are some: an empty label would be an
    /// invisible mark nobody can select again.
    func commitTyping() {
        guard var shape = typing else { return }
        typing = nil
        shape.text = shape.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text = shape.text, !text.isEmpty else { return }
        document.add(shape)
        publish()
    }

    func erase(at point: MarkupPoint) {
        guard let hit = shapes.last(where: { MarkupGeometry.hits(shape: $0, point: point, tolerance: 6) })
        else { return }
        document.apply { StepNumbering.renumbered($0.filter { $0.id != hit.id }) }
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
