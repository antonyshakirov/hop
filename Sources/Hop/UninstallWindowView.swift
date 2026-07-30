import AppKit
import HopCore
import SwiftUI
import UniformTypeIdentifiers

/// The uninstaller's window: drop an app or pick one, see everything it left
/// behind with sizes, untick what should stay, and move the rest to the trash.
///
/// Two things this window refuses to do, because they are what the category is
/// known for: delete anything outright (it all goes to the trash, so a mistake
/// costs a restore rather than the file), and claim a clean sweep. The report
/// ends with what STAYED and why.
struct UninstallWindowView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var uninstall: UninstallController
    let lang: AppLanguage

    @State private var targeted = false

    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let report = uninstall.report {
                self.report(report)
            } else if uninstall.mode == .clean {
                cleanBody
            } else if uninstall.target == nil {
                uninstallPicker
            } else {
                appHeader
                traceList
                mixedNote
                footer
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // The window follows its content: with only the drop plate on screen a
        // fixed height left a dark void under it, the same gap the converter and
        // the archives had before they learned to fit (Anton, 2026-07-30).
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { model.uninstallContentHeight = geo.size.height }
                .onChange(of: geo.size.height) { _, height in
                    model.uninstallContentHeight = height
                }
        })
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.panelBackground)
        .snapshotAwareDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            Task {
                for provider in providers {
                    if let url = await DroppedFiles.url(from: provider) {
                        uninstall.choose(path: url.path)
                        break
                    }
                }
            }
            return true
        }
    }

    // MARK: - Head

    private var header: some View {
        HStack {
            Text(t(uninstall.mode == .clean ? .uninstallModeClean : .uninstallLabel))
                .font(Theme.mono(13, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if uninstall.target != nil || uninstall.report != nil {
                Button(t(.uninstallAnother)) { uninstall.reset() }
                    .buttonStyle(.plain)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textSecondary)
                    .hoverDim()
            }
            Button { uninstall.promptToChoose() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight(5)
            .help(t(.uninstallPick))
        }
    }

    /// Removing an app: the drop plate, then every app on this Mac, so a removal is
    /// a click and not only a drag (Anton, 2026-07-30).
    private var uninstallPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            dropPlate
            Text(t(.uninstallPickApp))
                .font(Theme.mono(9))
                .foregroundStyle(Theme.textTertiary)
            ScrollView(showsIndicators: true) {
                VStack(spacing: 3) {
                    ForEach(uninstall.installedApps) { app in
                        Button { uninstall.choose(path: app.path) } label: {
                            HStack(spacing: 8) {
                                Image(nsImage: app.icon)
                                    .resizable()
                                    .frame(width: 18, height: 18)
                                Text(app.name)
                                    .font(Theme.mono(10.5))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(app.identifier)
                                    .font(Theme.mono(8))
                                    .foregroundStyle(Theme.textTertiary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 6))
                        .hoverHighlight(6)
                    }
                }
            }
            .frame(maxHeight: 260)
        }
    }

    /// Everything that is cleaning up rather than removing: caches by app,
    /// installers, leftovers of apps long gone, and the trash. One screen, because
    /// they are one intention and three of them do not deserve three windows.
    private var cleanBody: some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                ownerSection(title: t(.uninstallAllCaches), owners: uninstall.cacheOwners,
                             action: t(.uninstallClearCache)) { index in
                    uninstall.cacheOwners[index].ticked.toggle()
                } run: {
                    uninstall.clearTickedCaches()
                }
                if !uninstall.leftovers.isEmpty {
                    ownerSection(title: t(.uninstallLeftovers), owners: uninstall.leftovers,
                                 action: t(.uninstallRemoveLeftovers)) { index in
                        uninstall.leftovers[index].ticked.toggle()
                    } run: {
                        uninstall.removeTickedLeftovers()
                    }
                }
                installersBody
                heavySection
                trashSection
            }
            .padding(.bottom, 4)
        }
    }

    /// A list of apps (or identifiers) with a size each and one button.
    @ViewBuilder private func ownerSection(
        title: String, owners: [UninstallController.CacheOwner], action: String,
        toggle: @escaping (Int) -> Void, run: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.mono(9))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(owners.enumerated()), id: \.element.id) { index, owner in
                HStack(spacing: 8) {
                    Button { toggle(index) } label: {
                        Image(systemName: owner.ticked ? "checkmark.square.fill" : "square")
                            .font(.system(size: 12))
                            .foregroundStyle(owner.ticked ? Theme.textPrimary : Theme.textTertiary)
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverDim()
                    VStack(alignment: .leading, spacing: 1) {
                        Text(owner.name)
                            .font(Theme.mono(10.5))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if owner.isOrphan {
                            Text(t(.uninstallOrphanCache))
                                .font(Theme.mono(8))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(Self.sizeText(owner.bytes))
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 6))
            }
            HStack {
                Spacer()
                Button(action: run) {
                    Text(action)
                        .font(Theme.mono(10, weight: .bold))
                        .foregroundStyle(Theme.playFg)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Theme.playBg, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverDim()
                .disabled(!owners.contains(where: \.ticked))
            }
        }
    }

    /// Big app data with no tick and no button: the honest answer to "why is
    /// Telegram not in the cache list" is that its 23 GB is cache and data in one
    /// folder, and only Telegram knows which is which.
    @ViewBuilder private var heavySection: some View {
        if !uninstall.heavyData.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(t(.uninstallHeavySection))
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(uninstall.heavyData) { owner in
                    HStack(spacing: 8) {
                        Text(owner.name)
                            .font(Theme.mono(10.5))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(Self.sizeText(owner.bytes))
                            .font(Theme.mono(9))
                            .foregroundStyle(Theme.textTertiary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    /// The trash, with a number and the only irreversible button in the module.
    private var trashSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t(.uninstallTrashSection))
                .font(Theme.mono(9))
                .foregroundStyle(Theme.textTertiary)
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                Text("\(uninstall.trashItems) · \(Self.sizeText(uninstall.trashBytes))")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                Spacer()
                Button { uninstall.emptyTrash() } label: {
                    HoverLabel(text: t(.uninstallEmptyTrash), size: 10, color: Theme.accentRed)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(uninstall.trashItems == 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 6))
            Text(t(.uninstallEmptyTrashNote))
                .font(Theme.mono(8.5))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What the cache mode will not touch, with its size: the honest half of
    /// "clear the cache".
    @ViewBuilder private var mixedNote: some View {
        if uninstall.mode == .clean, !uninstall.mixed.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(t(.uninstallMixedNote))
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(uninstall.mixed) { trace in
                    Text("• \(trace.name) · \(Self.sizeText(trace.bytes))")
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    /// The installers list: no app involved, so it has its own body and its own
    /// button.
    private var installersBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t(.uninstallInstallersNote))
                .font(Theme.mono(9))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if uninstall.installers.isEmpty {
                Text(t(.uninstallNoInstallers))
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, 10)
            } else {
                ScrollView(showsIndicators: true) {
                    VStack(spacing: 4) {
                        ForEach(Array(uninstall.installers.enumerated()), id: \.element.id) {
                            index, file in
                            HStack(spacing: 8) {
                                Button { uninstall.installers[index].ticked.toggle() } label: {
                                    Image(systemName: file.ticked
                                          ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 12))
                                        .foregroundStyle(file.ticked
                                                         ? Theme.textPrimary : Theme.textTertiary)
                                        .frame(width: 18, height: 18)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .hoverDim()
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(file.found.name)
                                        .font(Theme.mono(10.5))
                                        .foregroundStyle(Theme.textPrimary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Text(Self.dateText(file.found.modified))
                                        .font(Theme.mono(8.5))
                                        .foregroundStyle(Theme.textTertiary)
                                }
                                Spacer(minLength: 8)
                                Text(Self.sizeText(file.found.bytes))
                                    .font(Theme.mono(9))
                                    .foregroundStyle(Theme.textTertiary)
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .frame(maxHeight: 300)
                HStack {
                    Spacer()
                    Button { uninstall.removeTickedInstallers() } label: {
                        Text(t(.uninstallRemoveInstallers))
                            .font(Theme.mono(10, weight: .bold))
                            .foregroundStyle(Theme.playFg)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Theme.playBg, in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverDim()
                    .disabled(!uninstall.installers.contains(where: \.ticked))
                }
            }
        }
    }

    /// A size a person can read: gigabytes when it is gigabytes, megabytes when it
    /// is not. A list of "0.0 GB" says nothing about which row is worth a click
    /// (Anton, 2026-07-30).
    static func sizeText(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_000_000
        return mb >= 10 ? String(format: "%.0f MB", mb) : String(format: "%.1f MB", mb)
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private var dropPlate: some View {
        VStack(spacing: 8) {
            Image(systemName: "trash")
                .font(.system(size: 22))
                .foregroundStyle(targeted ? Theme.editing : Theme.textTertiary)
            Text(t(.uninstallDrop))
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Text(t(.uninstallTrashNote))
                .font(Theme.mono(9))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(targeted ? Theme.editing : Theme.divider,
                        style: StrokeStyle(lineWidth: 1, dash: targeted ? [] : [4, 4]))
        )
    }

    @ViewBuilder private var appHeader: some View {
        if let target = uninstall.target {
            HStack(spacing: 10) {
                Image(nsImage: target.icon)
                    .resizable()
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.name)
                        .font(Theme.mono(12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(target.bundleIdentifier.isEmpty ? target.path : target.bundleIdentifier)
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
        }
    }

    // MARK: - What was found

    private var traceList: some View {
        ScrollView(showsIndicators: true) {
            VStack(spacing: 4) {
                ForEach(Array(uninstall.traces.enumerated()), id: \.element.id) { index, trace in
                    row(trace, index: index)
                }
                if uninstall.traces.isEmpty, uninstall.state != .scanning {
                    Text(t(.uninstallNothingFound))
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.vertical, 12)
                }
            }
        }
        .frame(maxHeight: 320)
    }

    private func row(_ trace: UninstallController.Trace, index: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                uninstall.traces[index].ticked.toggle()
            } label: {
                Image(systemName: trace.ticked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundStyle(trace.ticked ? Theme.textPrimary : Theme.textTertiary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverDim()
            VStack(alignment: .leading, spacing: 1) {
                Text(trace.name)
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(trace.path)
                        .font(Theme.mono(8.5))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    if trace.candidate.shared {
                        badge(t(.uninstallShared), color: Theme.accentYellow)
                    } else if !trace.candidate.byIdentifier {
                        badge(t(.uninstallByName), color: Theme.textTertiary)
                    }
                    if AppUninstall.needsAdmin(path: trace.path, kind: trace.kind) {
                        badge(t(.uninstallNeedsAdmin), color: Theme.textTertiary)
                    }
                }
            }
            Spacer(minLength: 8)
            Text(Self.sizeText(trace.bytes))
                .font(Theme.mono(9))
                .foregroundStyle(Theme.textTertiary)
                .monospacedDigit()
                .opacity(trace.bytes > 10_000_000 ? 1 : 0)   // hide noise for tiny plists
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 6))
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Theme.mono(8, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Theme.chipBg, in: RoundedRectangle(cornerRadius: 3))
    }

    // MARK: - Foot

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if uninstall.blockedByRunning {
                Text(t(.uninstallCantQuit))
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.accentRed)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Text(t(.uninstallTrashNote))
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button {
                    Task { await uninstall.removeTicked() }
                } label: {
                    Text(uninstall.needsAdmin ? t(.uninstallRemoveAdmin)
                                              : t(.uninstallRemove))
                        .font(Theme.mono(10, weight: .bold))
                        .foregroundStyle(Theme.playFg)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Theme.playBg, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverDim()
                .disabled(uninstall.state == .working || uninstall.totalBytes == 0
                          && !uninstall.traces.contains(where: \.ticked))
            }
        }
    }

    private func report(_ report: UninstallController.Report) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(t(.uninstallDone)) · \(report.trashed)")
                .font(Theme.mono(11, weight: .semibold))
                .foregroundStyle(Theme.accentGreen)
            if !report.failed.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t(.uninstallFailed))
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.accentRed)
                    ForEach(report.failed, id: \.self) { path in
                        Text(path)
                            .font(Theme.mono(8.5))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
            }
            // Refused by macOS rather than failed: the fix is a switch in System
            // Settings, and saying so is the difference between a dead end and a
            // next step.
            if !report.needsFullDisk.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t(.uninstallNeedsFullDisk))
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.accentYellow)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(report.needsFullDisk, id: \.self) { path in
                        Text(path)
                            .font(Theme.mono(8.5))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    Button {
                        if let url = URL(string:
                            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HoverLabel(text: t(.uninstallOpenFullDisk), size: 9.5,
                                   color: Theme.textSecondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            // The honest half: what no uninstaller can take away.
            VStack(alignment: .leading, spacing: 3) {
                Text(t(.uninstallStayed))
                    .font(Theme.mono(10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                ForEach(report.stayed, id: \.rawValue) { item in
                    Text("• " + t(Self.remainderKey(item)))
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private static func remainderKey(_ item: AppUninstall.Remainder) -> L10nKey {
        switch item {
        case .spotlight: return .uninstallLeftSpotlight
        case .systemLogs: return .uninstallLeftLogs
        case .keychain: return .uninstallLeftKeychain
        case .systemExtension: return .uninstallLeftExtension
        }
    }
}
