import Foundation

/// Which "what's new" card the panel owes the user, and how long it owes it.
///
/// The app had no way of telling anyone what a release brought (Anton,
/// 2026-08-30). The one banner it had asks whether to switch new MODULES on, so
/// a release that only deepened the modules already there — projects and history
/// in the tracker, platform presets in the converter, mkv and webm — announced
/// itself nowhere, and the full notes sat in the help behind a tab nobody opens.
///
/// A card is declared per release rather than derived from the version: a fix
/// rolled out on top of a release usually gets no card written for it, so there
/// is nothing to suppress. Usually — a release that changes something for
/// everybody earns one whatever its number, which is why a card is placed by its
/// full version and 1.9.1 is a card of its own rather than the 1.9 one again.
///
/// Nothing here talks to the system or to storage. It is given the cards and
/// their state and returns the one to draw, which is what makes every rule below
/// testable.
public struct ReleaseNews {

    /// A version as a card is placed by it: three numbers, the third defaulting
    /// to zero so that the card written as "1.9" still stands on 1.9.1.
    public struct Version: Comparable, Equatable, Sendable {
        public let major: Int
        public let minor: Int
        public let patch: Int

        /// nil for anything that is not a version, which is the only safe answer:
        /// a card that cannot be placed against the running build is not shown.
        public init?(_ text: String) {
            let parts = text.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count >= 2, let major = Int(parts[0]), let minor = Int(parts[1]),
                  major >= 0, minor >= 0 else { return nil }
            self.major = major
            self.minor = minor
            self.patch = parts.count > 2 ? (Int(parts[2]).map { max($0, 0) } ?? 0) : 0
        }

        public static func < (a: Version, b: Version) -> Bool {
            (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
        }
    }

    /// How long a card may stand after the moment it was first drawn. It leaves
    /// on its own so that somebody who neither reads nor dismisses it does not
    /// carry it at the top of the panel for the rest of the release.
    public static let life: TimeInterval = 2 * 24 * 60 * 60
    /// How many panel openings may draw it. Two: one to notice it is there, one
    /// to read it. Whichever of the two limits runs out first ends the card.
    public static let openings = 2

    /// One card and everything remembered about it.
    public struct Card: Equatable, Sendable {
        /// The release it speaks for, "1.9". Also the id its state is stored
        /// under.
        public let id: String
        /// The user pressed one of its buttons.
        public let seen: Bool
        /// Panel openings that drew it.
        public let shownCount: Int
        /// When it was first drawn, or nil while it never has been.
        public let firstShownAt: Date?

        public init(id: String, seen: Bool = false, shownCount: Int = 0,
                    firstShownAt: Date? = nil) {
            self.id = id
            self.seen = seen
            self.shownCount = shownCount
            self.firstShownAt = firstShownAt
        }
    }

    /// The card to draw now, or nil.
    ///
    /// The NEWEST one that still has something to say, never a queue of them: a
    /// user who skipped two releases wants to know where the app stands, not to
    /// dismiss its history one card at a time. The ones it passes over are
    /// `overtaken`, which the caller marks seen so they cannot surface later.
    public static func visible(_ cards: [Card], installed: String,
                               now: Date) -> Card? {
        guard let running = Version(installed) else { return nil }
        let mine = cards
            .compactMap { card -> (Card, Version)? in
                guard let version = Version(card.id), version <= running else { return nil }
                return (card, version)
            }
            .sorted { $0.1 < $1.1 }
        guard let newest = mine.last?.0 else { return nil }
        return isAlive(newest, now: now) ? newest : nil
    }

    /// The cards `visible` passed over, which have had their chance and should
    /// not come back on a later release.
    public static func overtaken(_ cards: [Card], installed: String) -> [Card] {
        guard let running = Version(installed) else { return [] }
        let mine = cards
            .compactMap { card -> (Card, Version)? in
                guard let version = Version(card.id), version <= running else { return nil }
                return (card, version)
            }
            .sorted { $0.1 < $1.1 }
        return mine.dropLast().map(\.0).filter { !$0.seen }
    }

    /// Whether a card still has a showing left in it.
    static func isAlive(_ card: Card, now: Date) -> Bool {
        if card.seen { return false }
        if card.shownCount >= openings { return false }
        if let first = card.firstShownAt, now.timeIntervalSince(first) >= life { return false }
        return true
    }
}
