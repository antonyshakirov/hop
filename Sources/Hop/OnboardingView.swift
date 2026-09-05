import HopCore
import ServiceManagement
import SwiftUI

/// First-launch wizard: one thing per screen, a step remembered across quits and
/// restarts, and no way out except through it.
/// SPEC: docs/spec.md — "Onboarding".
struct OnboardingView: View {
    let updater: UpdateChecker
    /// The app's own shelves store, so a grid chosen here is the same grid the
    /// panel shows a moment later.
    @ObservedObject var shelves: AppShelvesController
    let finish: () -> Void

    private enum Phase {
        case steps
        case checking
        case offer(UpdateChecker.ReleaseInfo)
    }
    @State private var phase: Phase = .steps

    @AppStorage(SettingsKey.appLanguage) private var languageRaw = "auto"
    @AppStorage(Theme.themeKey) private var themeRaw = "auto"
    @AppStorage(SettingsKey.onboardingStep) private var stepRaw = OnboardStep.welcome.rawValue
    /// A grid of apps is not a module until one exists, so the answer is kept
    /// here and acted on at the end.
    @AppStorage(SettingsKey.onboardingWantsApps) private var wantsApps = true
    @State private var launchAtLogin = true
    /// Bumped by every switch so the module rows redraw: their state lives in
    /// stored defaults, which SwiftUI does not observe.
    @State private var moduleRevision = 0

    /// Grids of apps are not in the registry — the module only exists once a
    /// grid does — so the checklist carries them under a key of their own.
    static let appsChoice = "apps"

    private var step: OnboardStep { OnboardStep.stored(stepRaw) }
    private var lang: AppLanguage { L10n.resolve(languageRaw) }
    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }

    var body: some View {
        VStack(spacing: 0) {
            SnapshotAwareScroll {
                content
                    .padding(.horizontal, 30)
                    .padding(.top, 28)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            footer
        }
        .frame(width: 620, height: 560)
        .background(Theme.panelBackground)
    }

    // MARK: - Steps

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: welcomeStep
        case .privacy: privacyStep
        case .permissions: permissionsStep
        case .done: doneStep
        default:
            if let index = step.groupIndex {
                groupStep(ModuleGroup.all[index])
            }
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 18) {
            VStack(spacing: 9) {
                asterisk // vector: the menu bar bitmap got blurry when scaled up
                Text("hop")
                    .font(Theme.mono(17, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(t(.onbWelcomeBody))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)

            SettingsCard {
                HStack {
                    Text(t(.language))
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    LanguagePicker(selection: $languageRaw)
                }
                SettingsRule()
                HStack {
                    Text(t(.themeLabel))
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    themeChip("auto", t(.themeAuto))
                    themeChip("dark", t(.themeDark))
                    themeChip("light", t(.themeLight))
                }
                SettingsRule()
                HStack {
                    Text(t(.launchAtLogin))
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Theme.MiniSwitch(isOn: $launchAtLogin)
                }
            }
        }
    }

    private var privacyStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeading(t(.permPledgeTitle))
            Text(t(.permPledgeBody))
                .font(Theme.mono(11))
                .foregroundStyle(Theme.docText)
                .fixedSize(horizontal: false, vertical: true)
            SettingsCard {
                VStack(alignment: .leading, spacing: 5) {
                    Text(t(.onbFreeTitle))
                        .font(Theme.mono(11, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(t(.onbFreeBody))
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.docText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Link(destination: URL(string: "https://github.com/antonyshakirov/hop")!) {
                HStack(spacing: 5) {
                    Text(t(.permPledgeLink))
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 8, weight: .semibold))
                }
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textTertiary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverDim()
        }
    }

    private func groupStep(_ group: ModuleGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeading(t(group.titleKey), subtitle: t(.onbGroupHint))
            SettingsCard {
                ForEach(Array(group.modules.enumerated()), id: \.element) { index, key in
                    if index > 0 { SettingsRule() }
                    moduleRow(key)
                }
            }
        }
    }

    private func moduleRow(_ key: String) -> some View {
        let isOn = Binding<Bool>(
            get: { moduleIsOn(key) },
            set: { setModule(key, on: $0) }
        )
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: ModulePresentation.icon(key == Self.appsChoice ? "apps" : key))
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.chipBg))
            VStack(alignment: .leading, spacing: 3) {
                Text(moduleTitle(key))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                if let purpose = purposeKey(key) {
                    Text(t(purpose))
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if key == "torrent" {
                    Text(t(.torrentEngineNote))
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Theme.MiniSwitch(isOn: isOn)
                .padding(.top, 6)
        }
        .id("\(key)-\(moduleRevision)")
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeading(t(.permTab), subtitle: t(.onbPermBody))
            PermissionsView(lang: lang)
        }
    }

    private var doneStep: some View {
        VStack(spacing: 16) {
            asterisk
                .padding(.top, 20)
            Text(t(.onbDoneTitle))
                .font(Theme.mono(17, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(t(.onbDoneBody))
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 400)
            if case .offer(let info) = phase {
                VStack(spacing: 10) {
                    Text(L10n.fill(.updateAvailable, lang, info.version))
                        .font(Theme.mono(11, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Button {
                        Task { await updater.install(info) } // restarts on its own
                    } label: {
                        Text(t(.updateNow))
                            .font(Theme.mono(12, weight: .bold))
                            .foregroundStyle(Theme.playFg)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Theme.playBg, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(t(.updateNow))
                    .hoverDim()
                }
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Chrome

    private func stepHeading(_ title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.mono(16, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 2)
    }

    /// Back, the step dots, and the one button forward. There is no close and no
    /// skip: the wizard is the only way in (Anton, 2026-09-05).
    private var footer: some View {
        HStack(spacing: 12) {
            Button { goBack() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverDim()
            .help(t(.onbBack))
            .opacity(step == .welcome ? 0 : 1)
            .disabled(step == .welcome)

            HStack(spacing: 5) {
                ForEach(OnboardStep.ordered, id: \.rawValue) { s in
                    Capsule()
                        .fill(s == step ? Theme.textPrimary : Theme.divider)
                        .frame(width: s == step ? 14 : 5, height: 4)
                }
            }
            Spacer()
            Button { goForward() } label: {
                Text(step == .done ? t(.onboardStart) : t(.onbNext))
                    .font(Theme.mono(12, weight: .bold))
                    .foregroundStyle(Theme.playFg)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 9)
                    .background(Theme.playBg, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .hoverDim()
            .disabled(isBusy)
            .opacity(isBusy ? 0.5 : 1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Theme.rowBg)
        .overlay(alignment: .top) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }

    private var isBusy: Bool {
        if case .checking = phase { return true }
        return false
    }

    private func goBack() {
        let all = OnboardStep.ordered
        guard let i = all.firstIndex(of: step), i > 0 else { return }
        stepRaw = all[i - 1].rawValue
    }

    private func goForward() {
        let all = OnboardStep.ordered
        guard let i = all.firstIndex(of: step) else { return }
        if i + 1 < all.count {
            stepRaw = all[i + 1].rawValue
            if all[i + 1] == .done { checkForUpdate() }
        } else {
            finishOnboarding()
        }
    }

    // MARK: - Module state

    /// The switches write straight through to the stored arrangement, so the
    /// answers survive the restart a permission asks for.
    private func moduleIsOn(_ key: String) -> Bool {
        key == Self.appsChoice ? wantsApps : !PanelView.storedModuleIsInactive(key)
    }

    private func setModule(_ key: String, on: Bool) {
        if key == Self.appsChoice {
            wantsApps = on
        } else if on {
            PanelView.activateStoredModule(key)
        } else {
            PanelView.deactivateStoredModule(key)
        }
        ModuleActivation.announceChange()
        moduleRevision += 1
    }

    private func moduleTitle(_ key: String) -> String {
        if key == Self.appsChoice { return t(.appsLabel) }
        return ModulePresentation.titleKey(key).map { t($0) } ?? key
    }

    private func purposeKey(_ key: String) -> L10nKey? {
        key == Self.appsChoice ? .purposeApps : ModulePresentation.purposeKey(key)
    }

    // MARK: - Pieces

    /// Color taken directly from the theme picked in the form — the global
    /// Theme.isDark lagged behind here during a live switch.
    private var asteriskColor: Color {
        switch themeRaw {
        case "dark": return .white
        case "light": return Color(white: 0.05)
        default: return Theme.systemDark ? .white : Color(white: 0.05)
        }
    }

    private var asterisk: some View {
        // geometry 1:1 with the menu bar icon: 8 rays offset by half a step
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = size.width * 0.38
            for ray in 0..<8 {
                let angle = CGFloat(ray) * .pi / 4 + .pi / 8
                var path = Path()
                path.move(to: center)
                path.addLine(to: CGPoint(
                    x: center.x + cos(angle) * radius,
                    y: center.y + sin(angle) * radius
                ))
                ctx.stroke(path, with: .color(asteriskColor),
                           style: StrokeStyle(lineWidth: size.width * 0.095, lineCap: .round))
            }
        }
        .frame(width: 44, height: 44)
        // SwiftUI does not redraw a Canvas with no input dependencies on a
        // theme change — the id forces it to be recreated with the new color
        .id(themeRaw)
    }

    private func themeChip(_ raw: String, _ label: String) -> some View {
        SettingChip(label, active: themeRaw == raw) { themeRaw = raw }
    }

    // MARK: - Finishing

    private func checkForUpdate() {
        phase = .checking
        Task {
            if let info = await updater.newerReleaseIfAny() {
                phase = .offer(info)
            } else {
                phase = .steps
            }
        }
    }

    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboardingDone")
        UserDefaults.standard.removeObject(forKey: SettingsKey.onboardingStep)
        // Apps is the one choice that has nothing to switch on: the module only
        // exists once a grid does, so saying yes here makes the first one.
        if wantsApps {
            PanelView.activateStoredModule(shelves.addShelf())
        }
        // Switching the monitor / tracker / to-dos off can empty their canonical
        // spaces (space 2, space 3); drop any that ended up empty so the app
        // never opens onto a blank tab.
        PanelView.dropEmptyOnboardingSpaces()
        // Mark EVERY "what's new" announcement as seen — the top-of-panel banner
        // exists for people who updated INTO a feature, and this user has just
        // been asked about all of them by name. Listing the ids by hand meant a
        // new announcement started greeting fresh installs with a question they
        // had already answered (Anton, 2026-07-29).
        for id in PanelView.featureAnnouncementIDs {
            UserDefaults.standard.set(true, forKey: "featureSeen.\(id)")
        }
        // The release cards go with them, for the same reason: a fresh install
        // has no release to catch up on — everything the cards announce is
        // simply how the app it just installed works.
        for id in PanelView.releaseCardIDs {
            UserDefaults.standard.set(true, forKey: PanelView.newsSeenKey(id))
        }
        if launchAtLogin {
            try? SMAppServiceHelper.enableLaunchAtLogin()
        }
        finish()
    }
}

enum SMAppServiceHelper {
    static func enableLaunchAtLogin() throws {
        guard Bundle.main.bundleIdentifier != nil else { return }
        if SMAppService.mainApp.status != .enabled {
            try SMAppService.mainApp.register()
        }
    }
}
