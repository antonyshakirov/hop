import Foundation
import HopCore

/// The onboarding's running order. What is stored is the INDEX in `ordered`: the
/// group screens are generated from the catalog, so they have no cases of their
/// own to number, and numbering them by arithmetic on a raw value collapsed all
/// six into one step.
/// SPEC: docs/spec.md — "Onboarding".
enum OnboardStep: Equatable {
    case welcome
    case privacy
    case modules(Int)
    case permissions
    case done

    static var ordered: [OnboardStep] {
        [.welcome, .privacy]
            + (0..<ModuleGroup.all.count).map { OnboardStep.modules($0) }
            + [.permissions, .done]
    }

    var groupIndex: Int? {
        if case .modules(let i) = self { return i }
        return nil
    }

    /// Where a stored index lands, clamped to a step that exists.
    static func stored(_ index: Int) -> OnboardStep {
        let all = ordered
        guard index >= 0, index < all.count else { return .welcome }
        return all[index]
    }

    static func index(of step: OnboardStep) -> Int {
        ordered.firstIndex(of: step) ?? 0
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
