import Foundation

/// Colour and width per tool, with the colour optionally held in common.
/// SPEC: docs/spec.md — "Screenshot (capture and mark up)"
/// Tests: Tests/HopCoreTests/MarkupInkBookTests.swift
public struct MarkupInkBook: Equatable, Sendable {
    public private(set) var shared: Bool
    private var inks: [MarkupTool: MarkupInk]
    private var common: String?

    public init(inks: [MarkupTool: MarkupInk] = [:], shared: Bool = false, common: String? = nil) {
        self.inks = inks
        self.shared = shared
        self.common = common
    }

    public var stored: [MarkupTool: MarkupInk] { inks }
    public var commonColour: String? { common }

    public func ink(for tool: MarkupTool, standard: (MarkupTool) -> MarkupInk) -> MarkupInk {
        let own = inks[tool] ?? standard(tool)
        guard shared, let common else { return own }
        return MarkupInk(hex: common, width: own.width)
    }

    /// A colour set while colours are shared is set for every tool; the width
    /// is always the one tool's own.
    public mutating func set(_ ink: MarkupInk, for tool: MarkupTool, standard: (MarkupTool) -> MarkupInk) {
        inks[tool] = ink
        guard shared else { return }
        common = ink.hex
        for other in MarkupTool.allCases where other != tool {
            inks[other] = MarkupInk(hex: ink.hex, width: (inks[other] ?? standard(other)).width)
        }
    }

    /// Thrown either way, the switch takes the colour in hand with it.
    public mutating func share(_ on: Bool, from tool: MarkupTool, standard: (MarkupTool) -> MarkupInk) {
        guard on != shared else { return }
        let colour = ink(for: tool, standard: standard).hex
        shared = on
        common = on ? colour : nil
        for other in MarkupTool.allCases {
            inks[other] = MarkupInk(hex: colour, width: (inks[other] ?? standard(other)).width)
        }
    }
}
