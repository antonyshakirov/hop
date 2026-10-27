import Foundation
import HopCore

/// The onboarding's running order. What is stored is the INDEX in `ordered`: the
/// group screens are generated from the catalog, so they have no cases of their
/// own to number, and numbering them by arithmetic on a raw value collapsed all
/// six into one step.
/// SPEC: docs/spec.md — "Onboarding".
enum OnboardStep: Equatable {
    case welcome
    case setup
    case privacy
    case modules(Int)
    case layout
    case permissions
    case done

    static var ordered: [OnboardStep] {
        [.welcome, .setup, .privacy]
            + (0..<ModuleGroup.all.count).map { OnboardStep.modules($0) }
            + [.layout, .permissions, .done]
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

    /// Before the sound screen was inserted, network followed Mac at index 8.
    /// Keep a partially completed wizard on the screen the person left.
    static func migratedIndex(_ index: Int, from version: Int) -> Int {
        guard version == 0 else { return ordered.indices.contains(index) ? index : 0 }
        guard (0..<13).contains(index) else { return 0 }
        return index > 7 ? index + 1 : index
    }

    static func migrateStoredProgress(in defaults: UserDefaults) {
        guard defaults.integer(forKey: "onboardingSequenceVersion") == 0 else { return }
        let previous = defaults.integer(forKey: SettingsKey.onboardingStep)
        defaults.set(migratedIndex(previous, from: 0), forKey: SettingsKey.onboardingStep)
        defaults.set(1, forKey: "onboardingSequenceVersion")
    }
}

/// SPEC: docs/spec.md — "Onboarding".
struct ModuleGroup {
    let titleKey: L10nKey
    let modules: [String]

    static let all: [ModuleGroup] = ModuleCatalog.onboardingGroups.compactMap { group in
        L10nKey(rawValue: group.titleID).map {
            ModuleGroup(titleKey: $0, modules: group.modules)
        }
    }
}
