import XCTest
@testable import HopCore

/// Finder draws `CFBundleTypeIconFile` on every file Hop is the opener for, so
/// a type declared without its own document icon silently falls back to the app
/// icon and a folder of archives turns into a wall of identical app tiles. The
/// plist and the icon generator are edited in different places; these tests are
/// the only thing that keeps them in step.
final class DocumentIconDeclarationTests: XCTestCase {
    private let torrentType = "org.bittorrent.torrent"

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // HopCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
    }

    private func documentTypes() throws -> [[String: Any]] {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("scripts/Info.plist"))
        let plist = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil) as? [String: Any]
        return try XCTUnwrap(plist?["CFBundleDocumentTypes"] as? [[String: Any]])
    }

    /// Icon names the generator actually produces, read from its declaration
    /// table rather than from disk: the icns files are build output.
    private func generatedIconNames() throws -> Set<String> {
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent("scripts/make-doc-icons.swift"),
            encoding: .utf8)
        let pattern = try NSRegularExpression(pattern: #"iconName:\s*"([^"]+)""#)
        let range = NSRange(source.startIndex..., in: source)
        return Set(pattern.matches(in: source, range: range).compactMap {
            Range($0.range(at: 1), in: source).map { String(source[$0]) }
        })
    }

    func testEveryDeclaredTypeCarriesItsOwnDocumentIcon() throws {
        for entry in try documentTypes() {
            let name = entry["CFBundleTypeName"] as? String ?? "unnamed"
            let icon = entry["CFBundleTypeIconFile"] as? String
            XCTAssertNotNil(icon, "\(name) declares no document icon")
            XCTAssertNotEqual(
                icon, "AppIcon",
                "\(name) falls back to the app icon instead of a document icon")
        }
    }

    func testDocumentIconsAreNotShared() throws {
        let icons = try documentTypes().compactMap { $0["CFBundleTypeIconFile"] as? String }
        XCTAssertEqual(
            icons.count, Set(icons).count,
            "two document types share an icon, so their formats cannot be told apart")
    }

    func testPlistIconsMatchTheGenerator() throws {
        let declared = Set(try documentTypes().compactMap { $0["CFBundleTypeIconFile"] as? String })
        XCTAssertEqual(declared, try generatedIconNames())
    }

    func testEveryHandledArchiveTypeIsDeclaredExactlyOnce() throws {
        let declared = try documentTypes().flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }
        for type in ArchiveHandlerRules.handledContentTypes + [torrentType] {
            XCTAssertEqual(
                declared.filter { $0 == type }.count, 1,
                "\(type) must be declared once, with one icon")
        }
        XCTAssertEqual(
            Set(declared),
            Set(ArchiveHandlerRules.handledContentTypes + [torrentType]),
            "the plist declares a type the app has no rules for")
    }
}
