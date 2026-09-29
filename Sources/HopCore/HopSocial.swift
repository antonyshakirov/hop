import Foundation

/// SPEC: docs/spec.md — "The about page (settings window)", Hop's own profiles.
public enum HopSocial {
    public struct Link: Equatable, Sendable {
        public let label: String
        public let url: String
    }

    public static let all: [Link] = [
        Link(label: "Instagram", url: "https://www.instagram.com/hop.tools/"),
        Link(label: "X", url: "https://x.com/hoptools"),
    ]

    /// None in Russian: Anton's decision of 2026-09-28, Russian law.
    public static func links(forLanguage code: String) -> [Link] {
        code == "ru" ? [] : all
    }
}
