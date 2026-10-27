import XCTest
import HopCore
@testable import Hop

@MainActor
final class OnboardingSoundTests: XCTestCase {
    func testLegacyStepsKeepTheirMeaningWhenSoundGetsItsOwnScreen() {
        let expected: [OnboardStep] = [.welcome, .setup, .privacy,
            .modules(0), .modules(1), .modules(2), .modules(3), .modules(4),
            .modules(6), .modules(7), .layout, .permissions, .done]
        for index in expected.indices {
            let migrated = OnboardStep.migratedIndex(index, from: 0)
            XCTAssertEqual(OnboardStep.stored(migrated), expected[index], "legacy step \(index)")
        }
        XCTAssertEqual(OnboardStep.migratedIndex(-1, from: 0), 0)
        XCTAssertEqual(OnboardStep.migratedIndex(99, from: 0), 0)
        for index in OnboardStep.ordered.indices {
            XCTAssertEqual(OnboardStep.migratedIndex(index, from: 1), index)
        }
    }

    func testStoredNetworkProgressMigratesOnlyOnceAcrossRelaunch() {
        let suite = "HopTests.OnboardingMigration." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(8, forKey: SettingsKey.onboardingStep)
        OnboardStep.migrateStoredProgress(in: defaults)
        XCTAssertEqual(defaults.integer(forKey: SettingsKey.onboardingStep), 9)
        XCTAssertEqual(defaults.integer(forKey: "onboardingSequenceVersion"), 1)
        OnboardStep.migrateStoredProgress(in: defaults)
        XCTAssertEqual(defaults.integer(forKey: SettingsKey.onboardingStep), 9)
    }

    func testTranslationsStayWithTheirLanguageDespiteTableOrdering() {
        let titles: [AppLanguage: String] = [.sr: "аудио миксер", .ar: "مازج الصوت",
            .he: "מיקסר שמע", .fa: "میکسر صدا", .ur: "آڈیو مکسر"]
        for (language, title) in titles {
            XCTAssertEqual(L10n.t(.onbSoundTitle, language).replacingOccurrences(of: "\u{00A0}", with: " "), title)
        }
    }

    private final class Session: SoundMixingSession {
        var stops = 0
        func outputs(_ channels: [SoundMixerChannel]) {}
        func configure(_ channel: SoundMixerChannel) {}
        func stop() { stops += 1 }
    }

    func testNewsModuleSwitchClearsTheResumeChoiceBeforeReactivation() {
        let suite = "HopTests.SoundNews." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = Session()
        var starts = 0
        let mixer = SoundMixerController(defaults: defaults, makeSession: { _ in
            starts += 1
            return session
        }, discover: { [] }, outputs: { [] })
        let model = AppModel(preview: true, mixerController: mixer, soundEnabled: { true })
        mixer.start()
        XCTAssertTrue(mixer.requested)
        model.stopSoundMixers()
        XCTAssertFalse(mixer.requested)
        XCTAssertFalse(mixer.running)
        mixer.resumeIfEnabled()
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(session.stops, 1)
    }

    func testMacPicturesStayTogetherAndSoundIsOnTheNextScreen() {
        let groups = ModuleGroup.all
        let mac = groups.firstIndex { $0.titleKey == .onbGroupMac }!
        XCTAssertEqual(groups[mac].modules, ["system", "awake", "keyboard"])
        XCTAssertEqual(groups[mac + 1].modules, ["sound"])
        XCTAssertEqual(groups.flatMap(\.modules).filter { $0 == "sound" }.count, 1)
    }

    func testSoundOnboardingUsesOneShortDescriptionInEveryLanguage() {
        for lang in AppLanguage.allCases {
            let body = L10n.t(.onbSoundBody, lang)
            XCTAssertFalse(body.isEmpty)
            XCTAssertFalse(body.contains("\n"))
            XCTAssertLessThan(body.count, 180, lang.rawValue)
        }
    }
}
