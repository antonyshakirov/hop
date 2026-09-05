import AppKit
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
    /// Hands the chosen theme to the app, windows included.
    var applyTheme: () -> Void = {}
    let finish: () -> Void

    private enum Phase {
        case steps
        case checking
        case offer(UpdateChecker.ReleaseInfo)
    }
    @State private var phase: Phase = .steps

    @AppStorage(SettingsKey.appLanguage) private var languageRaw = "auto"
    @AppStorage(Theme.themeKey) private var themeRaw = "auto"
    @AppStorage(SettingsKey.onboardingStep) private var stepIndex = 0
    /// A grid of apps is not a module until one exists, so the answer is kept
    /// here and acted on at the end.
    @AppStorage(SettingsKey.onboardingWantsApps) private var wantsApps = true
    /// Stored, not @State: the wizard is restarted by the permissions step, and
    /// an answer given on the first screen must still be there afterwards.
    @AppStorage(SettingsKey.onboardingLaunchAtLogin) private var launchAtLogin = true
    /// Bumped by every switch so the module rows redraw: their state lives in
    /// stored defaults, which SwiftUI does not observe.
    @State private var moduleRevision = 0
    @State private var entered = false
    /// Controllers of its own, with staged data: the pictures are the real
    /// modules, and must not touch what the person already has.
    @StateObject private var previewModel = AppModel(preview: true)

    /// Grids of apps are not in the registry — the module only exists once a
    /// grid does — so the checklist carries them under a key of their own.
    static let appsChoice = "apps"

    /// Window height minus the footer.
    private static let contentHeight: CGFloat = 600

    /// The module screens need room for a 368pt picture beside its text; a
    /// screen with one card underneath a heading does not, and a card stretched
    /// across the whole window reads as a stray band (Anton, 2026-09-05).
    private var contentWidth: CGFloat {
        switch step {
        case .welcome, .setup, .privacy, .done: return 520
        default: return 780
        }
    }

    private var step: OnboardStep { OnboardStep.stored(stepIndex) }
    private var lang: AppLanguage { L10n.resolve(languageRaw) }
    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }

    var body: some View {
        VStack(spacing: 0) {
            SnapshotAwareScroll {
                content
                    .frame(maxWidth: contentWidth)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 30)
                    // A short screen sits in the middle of the window rather
                    // than at the top of it; a long one (permissions) outgrows
                    // this and scrolls as usual.
                    .frame(maxWidth: .infinity, minHeight: Self.contentHeight, alignment: .center)
            }
            .frame(maxHeight: .infinity)
            footer
        }
        .frame(minWidth: 880, maxWidth: .infinity, minHeight: 700, maxHeight: .infinity)
        .background {
            Theme.panelBackground
            OnboardingBackdrop(focus: step == .welcome
                               ? UnitPoint(x: 0.5, y: 0.22) : UnitPoint(x: 0.5, y: 0.3))
        }
    }

    // MARK: - Steps

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: welcomeStep
        case .setup: setupStep
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
        VStack(spacing: 24) {
            VStack(spacing: 14) {
                asterisk(size: 84) // vector: the menu bar bitmap got blurry when scaled up
                    .modifier(Rises(after: 0, shown: entered))
                Text("hop")
                    .font(Theme.mono(30, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .modifier(Rises(after: 0.14, shown: entered))
                Text(t(.onbWelcomeBody))
                    .font(Theme.mono(13))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
                    .modifier(Rises(after: 0.28, shown: entered))
                Text(t(.onbWelcomeSetup))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textTertiary)
                    .modifier(Rises(after: 0.38, shown: entered))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 26)

            opaque(10) { SettingsCard {
                HStack {
                    Text(t(.language))
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    LanguagePicker(selection: $languageRaw)
                }
            } }
            .modifier(Rises(after: 0.5, shown: entered))
        }
        .onAppear { entered = true }
    }

    /// SPEC: docs/spec.md — "Onboarding".
    private struct Rises: ViewModifier {
        let after: Double
        let shown: Bool

        func body(content: Content) -> some View {
            let on = shown || Snapshot.active
            return content
                .opacity(on ? 1 : 0)
                .offset(y: on ? 0 : 14)
                .animation(.easeOut(duration: 0.45).delay(after), value: on)
        }
    }

    /// The second screen: what it looks like and when it starts. Split off the
    /// welcome, which is now the app introducing itself and asking one thing
    /// (Anton, 2026-09-05).
    private var setupStep: some View {
        VStack(spacing: 16) {
            stepHeading(t(.onbSetupTitle))
            opaque(10) { SettingsCard {
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
            } }
        }
    }

    private var privacyStep: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.textPrimary)
                .padding(.bottom, 6)
            stepHeading(t(.onbPrivacyTitle))
            VStack(spacing: 6) {
                privacyClaim("bolt.horizontal.circle", t(.onbPrivacyNoServer))
                privacyClaim("chart.bar.xaxis", t(.onbPrivacyNoAnalytics))
                privacyClaim("chevron.left.forwardslash.chevron.right", t(.onbPrivacyOpenSource))
            }
            // Plain text and two links under the cards: everything in a card
            // made the screen read as a list of buttons (Anton, 2026-09-05).
            Text(t(.onbFreeBody))
                .font(Theme.mono(12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 30)
            HStack(spacing: 18) {
                privacyLink("heart.fill", t(.donateTitle), url: donateURL, tint: Theme.iconHealth)
                privacyLink("chevron.left.forwardslash.chevron.right", t(.permPledgeLink),
                            url: "https://github.com/antonyshakirov/hop")
            }
        }
    }

    private func privacyLink(_ symbol: String, _ text: String,
                            url: String, tint: Color = Theme.textTertiary) -> some View {
        Button {
            if let link = URL(string: url) { NSWorkspace.shared.open(link) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 10))
                    .foregroundStyle(tint)
                Text(text)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverDim()
    }

    /// Russian routes to the ru card, every other locale to the neutral one —
    /// the same rule the settings page and the localized READMEs follow.
    private var donateURL: String {
        lang == .ru ? "https://web.tribute.tg/d/Nvp" : "https://web.tribute.tg/d/Nvk"
    }

    /// Every card sits on the panel's own colour: `Theme.rowBg` is 4.5% ink, so
    /// without this the backdrop's dots read straight through the cards
    /// (Anton, 2026-09-05).
    private func opaque<V: View>(_ radius: CGFloat, @ViewBuilder _ content: () -> V) -> some View {
        content().background(RoundedRectangle(cornerRadius: radius).fill(Theme.background))
    }

    /// One claim: mark and words as one group in the middle of a narrow card.
    /// With a `url` the whole card opens it and says so with the external-page
    /// glyph — the claim about open source is checkable, so it is a link
    /// (Anton, 2026-09-05).
    private func privacyClaim(_ symbol: String, _ text: String,
                              tint: Color = Theme.accentGreen) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(tint)
            Text(text)
                .font(Theme.mono(12))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.background))
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.controlStroke, lineWidth: 1))
        .frame(maxWidth: 360)
    }

    private func groupStep(_ group: ModuleGroup) -> some View {
        VStack(spacing: 16) {
            stepHeading(t(group.titleKey), subtitle: t(.onbGroupHint))
            VStack(spacing: 10) {
                ForEach(group.modules, id: \.self) { key in
                    opaque(10) { SettingsCard(spacing: 10) { moduleRow(key) } }
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
            // Each module carries its OWN picture, beside its own row: one
            // picture per screen said nothing about the two modules under it
            // (Anton, 2026-09-05).
            modulePreview(key)
            VStack(alignment: .leading, spacing: 3) {
                Text(moduleTitle(key))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                Text(moduleBlurb(key))
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.textTertiary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
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

    /// The module as it will actually look, drawn by the panel's own code with
    /// the preview model's staged data. Nothing to redraw per language or theme:
    /// it is the same view the panel shows.
    /// The module drawn by the panel's own code, scaled down to a thumbnail that
    /// sits beside its row. `scaleEffect` does not change the layout size, so the
    /// panel is laid out at its real 368pt and then cropped to the tile.
    private func modulePreview(_ key: String) -> some View {
        // The panel's own width, unscaled: at 170pt the rows were a grey blur
        // and said nothing about the module (Anton, 2026-09-05).
        // "apps" is not a module key: the launcher exists as a shelf, so the
        // preview asks the staged model for the one it made.
        let drawn = key == Self.appsChoice
            ? previewModel.appShelves.shelves.shelves.first.map { "apps:\($0.id.uuidString)" }
            : key
        return previewBody(drawn)
            .frame(width: 368, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .allowsHitTesting(false)
    }

    /// SPEC: docs/spec.md — "Onboarding", the module preview.
    @ViewBuilder
    private func previewBody(_ key: String?) -> some View {
        switch key {
        case "convert":
            ConvertWindowView(preview: true).environmentObject(previewModel)
        case "archive":
            ArchiveWindowView(preview: true).environmentObject(previewModel)
        case "ocr":
            ScreenTextArt(lang: lang)
        case "keyboard":
            KeyboardLockArt(lang: lang)
        case "uninstall":
            UninstallWindowView(uninstall: previewModel.uninstall, lang: lang, preview: true)
                .environmentObject(previewModel)
        default:
            PanelView(previewModules: [key].compactMap { $0 })
                .environmentObject(previewModel)
        }
    }

    private var permissionsStep: some View {
        VStack(spacing: 16) {
            stepHeading(t(.permTab), subtitle: t(.onbPermBody))
            PermissionsView(lang: lang, showsPledge: false, large: true)
        }
    }

    private var doneStep: some View {
        VStack(spacing: 18) {
            asterisk(size: 104)
                .padding(.top, 20)
            Text(t(.onbDoneTitle))
                .font(Theme.mono(28, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(t(.onbDoneBody))
                .font(Theme.mono(13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
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
        VStack(spacing: 8) {
            Text(title)
                .font(Theme.mono(21, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.mono(11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
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
                ForEach(Array(OnboardStep.ordered.enumerated()), id: \.offset) { index, _ in
                    Capsule()
                        .fill(index == stepIndex ? Theme.textPrimary : Theme.divider)
                        .frame(width: index == stepIndex ? 14 : 5, height: 4)
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
    }

    private var isBusy: Bool {
        if case .checking = phase { return true }
        return false
    }

    private func goBack() {
        guard stepIndex > 0 else { return }
        stepIndex -= 1
    }

    private func goForward() {
        let all = OnboardStep.ordered
        guard stepIndex + 1 < all.count else { return finishOnboarding() }
        stepIndex += 1
        if all[stepIndex] == .done { checkForUpdate() }
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

    /// SPEC: docs/spec.md — "Onboarding", the module description.
    private func moduleBlurb(_ key: String) -> String {
        let short = purposeKey(key).map { t($0) } ?? ""
        guard let doc = ModulePresentation.howKeys(key == Self.appsChoice ? "apps" : key).first
        else { return short }
        let opening = t(doc).components(separatedBy: "\n\n").first ?? ""
        if opening.count > 170, let stop = opening.prefix(170).lastIndex(of: ".") {
            return String(opening[..<stop]) + "."
        }
        return opening.count < 60 && !short.isEmpty ? "\(short). \(opening)" : opening
    }

    // MARK: - Pieces

    /// Color taken directly from the theme picked in the form — the global
    /// Theme.isDark lagged behind here during a live switch.
    private var asteriskColor: Color { Theme.accentYellow }

    private func asterisk(size: CGFloat = 44) -> some View {
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
        .frame(width: size, height: size)
        // SwiftUI does not redraw a Canvas with no input dependencies on a
        // theme change — the id forces it to be recreated with the new color
        .id(themeRaw)
    }

    /// Applying it to the WINDOW as well: a popover (the language list) is a
    /// window of its own and inherits the parent's appearance, so without this
    /// the list opened in the old theme — dark text on a dark sheet
    /// (Anton, 2026-09-05).
    private func themeChip(_ raw: String, _ label: String) -> some View {
        SettingChip(label, active: themeRaw == raw) {
            themeRaw = raw
            applyTheme()
        }
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
