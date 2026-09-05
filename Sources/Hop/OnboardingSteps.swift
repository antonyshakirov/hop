import Foundation
import HopCore

/// The onboarding's running order; raw values are stored.
/// SPEC: docs/spec.md — "Onboarding".
enum OnboardStep: Int, CaseIterable {
    case welcome = 0
    case privacy = 1
    case modules = 2          // + group index, see `group`
    case permissions = 100
    case done = 200

    static func modules(_ index: Int) -> OnboardStep {
        OnboardStep(rawValue: OnboardStep.modules.rawValue + index) ?? .privacy
    }

    /// Which group screen this step is, if it is one.
    var groupIndex: Int? {
        let base = OnboardStep.modules.rawValue
        guard rawValue >= base, rawValue < base + ModuleGroup.all.count else { return nil }
        return rawValue - base
    }

    static var ordered: [OnboardStep] {
        [.welcome, .privacy]
            + (0..<ModuleGroup.all.count).map { modules($0) }
            + [.permissions, .done]
    }

    static func stored(_ raw: Int) -> OnboardStep {
        ordered.first { $0.rawValue == raw } ?? .welcome
    }
}

/// SPEC: docs/spec.md — "Onboarding".
struct ModuleGroup {
    let titleKey: L10nKey
    let modules: [String]

    private static let titles: [L10nKey] = [
        .onbGroupTime, .onbGroupFiles, .onbGroupScreen,
        .onbGroupMac, .onbGroupNetwork, .onbGroupDesk,
    ]

    static let all: [ModuleGroup] = zip(titles, ModuleCatalog.onboardingGroups).map {
        ModuleGroup(titleKey: $0, modules: $1)
    }
}
