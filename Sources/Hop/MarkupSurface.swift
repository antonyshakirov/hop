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

    private let document = MarkupDocument()
    private var inks: [MarkupTool: MarkupInk] = [:]
    private var origin: MarkupPoint?
    private var ticker: Timer?
    private let opened = Date()

    var canUndo: Bool { document.canUndo }
    var canRedo: Bool { document.canRedo }

    /// Marks that are still worth drawing at this instant.
    var visible: [MarkupShape] {
        let living = FadingInk.alive(shapes, now: now)
        guard let drafting else { return living }
        return living + [drafting]
    }

    func ink(for tool: MarkupTool) -> MarkupInk {
        inks[tool] ?? Self.standardInk(for: tool)
    }

    func setInk(_ ink: MarkupInk, for tool: MarkupTool) {
        inks[tool] = ink
        objectWillChange.send()
    }

    func opacity(of shape: MarkupShape) -> Double {
        FadingInk.opacity(of: shape, now: now)
    }

    func begin(at point: MarkupPoint) {
        let stamp = Date().timeIntervalSince(opened)
        switch tool {
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

    func extend(to point: MarkupPoint) {
        guard var shape = drafting else { return }
        switch shape.tool {
        case .pencil, .fadingInk, .marker:
            shape.points.append(point)
        default:
            shape.points = [origin ?? point, point]
        }
        drafting = shape
    }

    func finish() {
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

    func dropCropFrames() {
        document.apply { $0.filter { $0.tool != .crop } }
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
        default: return MarkupInk(hex: "#FF453A", width: 4)
        }
    }
}

extension Color {
    init(markupHex: String) {
        guard let parts = ColorFormatting.components(markupHex) else {
            self = .red
            return
        }
        self = Color(red: Double(parts.r) / 255, green: Double(parts.g) / 255, blue: Double(parts.b) / 255)
    }
}
