import XCTest
@testable import HopCore

/// The risky half of an uninstaller is deciding that a folder belongs to the app
/// being removed and not to five others. That decision is pure, so it is tested —
/// including against the real entries three installed apps leave behind.
final class AppUninstallTests: XCTestCase {

    private let telegramID = "ru.keepcoder.Telegram"
    private let telegramName = "Telegram"

    private func match(_ entry: String, id: String? = nil, name: String? = nil)
    -> AppUninstall.MatchKind? {
        AppUninstall.match(entry: entry,
                           identifier: id ?? telegramID,
                           appName: name ?? telegramName)
    }

    // MARK: - The shapes a bundle identifier really takes

    func testTheIdentifierItself() {
        XCTAssertEqual(match("ru.keepcoder.Telegram"), .identifier)
    }

    func testAnExtensionsOwnContainer() {
        // Containers/ru.keepcoder.Telegram.TelegramShare
        XCTAssertEqual(match("ru.keepcoder.Telegram.TelegramShare"), .identifier)
    }

    func testATeamPrefixedGroupContainer() {
        // Group Containers/6N38VWS5BX.ru.keepcoder.Telegram
        XCTAssertEqual(match("6N38VWS5BX.ru.keepcoder.Telegram"), .identifier)
    }

    func testATeamPrefixedExtensionContainer() {
        XCTAssertEqual(match("6N38VWS5BX.ru.keepcoder.Telegram.TelegramShare"), .identifier)
    }

    func testAnUpdaterCacheBesideTheApp() {
        // Caches/com.microsoft.VSCode.ShipIt — Squirrel's own folder
        XCTAssertEqual(match("com.microsoft.VSCode.ShipIt",
                             id: "com.microsoft.VSCode", name: "Visual Studio Code"),
                       .identifier)
    }

    func testTheFileTypeComesOffBeforeMatching() {
        XCTAssertEqual(match("ru.keepcoder.Telegram.plist"), .identifier)
        XCTAssertEqual(match("ru.keepcoder.Telegram.savedState"), .identifier)
        XCTAssertEqual(match("ru.keepcoder.Telegram.binarycookies"), .identifier)
    }

    // MARK: - What must NOT match

    func testANeighbourWithTheSamePrefixIsNotTouched() {
        XCTAssertNil(match("com.acme.notesuite", id: "com.acme.notes", name: "Notes"),
                     "a prefix without the dot is a different app")
    }

    func testAnUnrelatedIdentifierIsNotTouched() {
        XCTAssertNil(match("com.other.telegram"))
        XCTAssertNil(match("SomethingElse"))
    }

    func testAnAppWhoseNameOnlyStartsTheEntryIsOffered() {
        // Application Support/Telegram Desktop for the app "Telegram"
        XCTAssertEqual(match("Telegram Desktop"), .namePrefix)
        XCTAssertNil(match("Telegramnook"), "no space, so it is another product")
    }

    func testTheExactNameMatches() {
        XCTAssertEqual(match("Telegram"), .exactName)
        XCTAssertEqual(match("telegram"), .exactName, "folder names are not case-sensitive here")
    }

    // MARK: - Ticked by default, or not

    func testIdentifierAndExactNameAreTicked() {
        let byID = AppUninstall.candidate(directory: "/lib", entry: telegramID, kind: .support,
                                          identifier: telegramID, appName: "Notes")
        XCTAssertTrue(byID?.ticked == true)
        let byName = AppUninstall.candidate(directory: "/lib", entry: "Notes", kind: .support,
                                            identifier: "com.acme.notes", appName: "Notes")
        XCTAssertEqual(byName?.match, .exactName)
        XCTAssertTrue(byName?.ticked == true, "this is where an app's gigabytes live")
    }

    func testANamePrefixIsListedUnticked() {
        let candidate = AppUninstall.candidate(directory: "/lib", entry: "Telegram Desktop",
                                               kind: .support, identifier: telegramID, appName: telegramName)
        XCTAssertEqual(candidate?.match, .namePrefix)
        XCTAssertFalse(candidate?.ticked == true)
    }

    func testAVendorFolderIsFlaggedAndNeverTicked() {
        let candidate = AppUninstall.candidate(directory: "/lib", entry: "Google", kind: .support,
                                               identifier: "com.google.Chrome", appName: "Google")
        XCTAssertTrue(candidate?.shared == true,
                      "Application Support/Google holds Drive's data too")
        XCTAssertFalse(candidate?.ticked == true)
    }

    // MARK: - launchd folders are stricter

    func testALaunchdFolderTakesOnlyIdentifierPlists() {
        XCTAssertNotNil(AppUninstall.candidate(directory: "/lib", entry: "\(telegramID).plist",
                                               kind: .launchAgent,
                                               identifier: telegramID, appName: telegramName))
        XCTAssertNil(AppUninstall.candidate(directory: "/lib", entry: "Telegram Desktop",
                                            kind: .launchAgent, identifier: telegramID, appName: telegramName),
                     "a label is not a display name")
        XCTAssertNil(AppUninstall.candidate(directory: "/lib", entry: telegramID, kind: .launchAgent,
                                            identifier: telegramID, appName: telegramName),
                     "a job is a .plist; anything else in there is not ours")
    }

    func testTheDomainFollowsWhereThePlistLives() {
        XCTAssertEqual(AppUninstall.launchdDomain(forDirectory: "/Library/LaunchDaemons", uid: 501),
                       "system")
        XCTAssertEqual(AppUninstall.launchdDomain(forDirectory: "/Users/t/Library/LaunchAgents",
                                                  uid: 501),
                       "gui/501")
    }

    // MARK: - Coverage and honesty

    func testEveryUserFolderThatMattersIsScanned() {
        let kinds = Set(AppUninstall.userFolders.map(\.kind))
        for expected: AppUninstall.Kind in [.support, .caches, .preferences, .container,
                                            .groupContainer, .appScripts, .savedState,
                                            .httpStorages, .webKit, .logs, .cookies,
                                            .launchAgent] {
            XCTAssertTrue(kinds.contains(expected), "missing \(expected)")
        }
    }

    func testEverySystemFolderNeedsAnAdministrator() {
        // The KIND is not enough: a plug-in folder exists in both trees, so the
        // decision follows the PATH.
        for folder in AppUninstall.systemFolders {
            XCTAssertTrue(AppUninstall.needsAdmin(path: "/Library/\(folder.name)/Thing",
                                                  kind: folder.kind),
                          "\(folder.name) is a system location")
        }
        XCTAssertFalse(AppUninstall.needsAdmin(path: "/Users/t/Library/QuickLook/Thing.qlgenerator",
                                               kind: .plugin),
                       "the same kind under a home folder is the user's own")
        XCTAssertTrue(AppUninstall.needsAdmin(path: "/var/db/receipts/x.bom", kind: .receipt))
    }

    func testTheThingsWeCannotRemoveAreNamed() {
        XCTAssertEqual(Set(AppUninstall.Remainder.allCases.map(\.rawValue)),
                       ["spotlight", "systemLogs", "keychain", "systemExtension"],
                       "receipts are ordinary files and are removed, not excused")
    }

    // MARK: - The places found later, by checking a real disk

    func testPerHostPreferencesAreFound() {
        // Preferences/ByHost/<id>.<hardware uuid>.plist
        XCTAssertEqual(match("com.anthropic.claudefordesktop.ShipIt.F6D57E21-A1B8-5272-8E20-C5936891D726",
                             id: "com.anthropic.claudefordesktop", name: "Claude"),
                       .identifier)
    }

    func testACrashReportBelongsToItsApp() {
        XCTAssertEqual(match("Hop-2026-07-25-173327", id: "com.x.hop", name: "Hop-2026-07-25-173327"),
                       .exactName)
        XCTAssertEqual(match("Claude_2026-07-30-120000.ips",
                             id: "com.anthropic.claudefordesktop", name: "Claude"),
                       .exactName, "macOS separates the name from the date with an underscore")
    }

    func testAReceiptIsRemovableAndNeedsAnAdministrator() {
        XCTAssertTrue(AppUninstall.Kind.receipt.needsAdmin)
        let bom = AppUninstall.candidate(directory: "/var/db/receipts",
                                         entry: "com.acme.notes.bom", kind: .receipt,
                                         identifier: "com.acme.notes", appName: "Notes")
        XCTAssertEqual(bom?.match, .identifier)
        XCTAssertTrue(bom?.ticked == true)
    }

    func testTheFoldersOutsideBothLibrariesAreListed() {
        let paths = AppUninstall.otherFolders.map(\.path)
        XCTAssertTrue(paths.contains("/var/db/receipts"))
        XCTAssertTrue(paths.contains("/Users/Shared"))
    }
}
