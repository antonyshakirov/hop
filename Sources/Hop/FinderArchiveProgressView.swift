import AppKit
import HopCore
import SwiftUI

@MainActor
final class FinderArchiveProgressModel: ObservableObject {
    @Published private(set) var batch: FinderArchiveBatchState

    init(files: [(id: UUID, fileName: String)]) {
        batch = FinderArchiveBatchState(files: files)
    }

    func receive(_ event: FinderArchiveProgressEvent, for id: UUID) {
        batch.receive(event, for: id)
    }
}

/// A short-lived window owned only by one Finder open event. It is deliberately
/// separate from ArchiveWindowView: a double-click is a command already in
/// progress, never input for the manual drop/paste queue.
@MainActor
final class FinderArchiveProgressWindowController: NSObject, NSWindowDelegate {
    let id = UUID()

    private let model: FinderArchiveProgressModel
    private let window: NSWindow
    private let onClose: (UUID) -> Void
    private let contentHeight: CGFloat

    init(
        files: [(id: UUID, fileName: String)],
        onClose: @escaping (UUID) -> Void
    ) {
        model = FinderArchiveProgressModel(files: files)
        self.onClose = onClose
        contentHeight = min(72 + CGFloat(files.count) * 50, 452)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = "Hop"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        self.window = window

        super.init()

        window.delegate = self
        let host = NSHostingController(
            rootView: FinderArchiveProgressView(model: model, lang: L10n.current))
        // The row count never changes, so an explicit fixed content height is
        // safer than preferredContentSize. Asking AppKit and SwiftUI to resize
        // each other while a progress row updates creates a constraint cycle.
        host.sizingOptions = []
        window.contentViewController = host
        window.contentMinSize = NSSize(width: 420, height: 100)
        window.contentMaxSize = NSSize(width: 420, height: 452)
    }

    func show() {
        applyTheme()
        window.setContentSize(NSSize(
            width: 420,
            height: max(contentHeight, 100)))
        window.contentView?.layoutSubtreeIfNeeded()
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func receive(_ event: FinderArchiveProgressEvent, for id: UUID) {
        model.receive(event, for: id)
        if model.batch.presentation == .close {
            window.close()
        }
    }

    func applyTheme() {
        window.appearance = NSAppearance(named: Theme.isDark ? .darkAqua : .aqua)
    }

    var presentedWindow: NSWindow {
        window
    }

    func windowWillClose(_ notification: Notification) {
        onClose(id)
    }
}

struct FinderArchiveProgressView: View {
    @ObservedObject var model: FinderArchiveProgressModel
    let lang: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: model.batch.presentation == .failure
                      ? "exclamationmark.triangle" : "archivebox")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(model.batch.presentation == .failure
                                     ? Theme.accentRed : Theme.textSecondary)
                Text(L10n.t(.archiveLabel, lang).capitalizedFirst)
                    .font(Theme.mono(12, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }

            if Snapshot.active {
                rows
            } else {
                ScrollView(.vertical) {
                    rows
                }
                .frame(height: min(CGFloat(model.batch.items.count) * 50, 380))
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(Theme.panelBackground)
    }

    private var rows: some View {
        VStack(spacing: 6) {
            ForEach(model.batch.items) { item in
                itemRow(item)
            }
        }
    }

    private func itemRow(_ item: FinderArchiveBatchState.Item) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.left.and.arrow.up.right")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 16)
            Text(item.progress.fileName)
                .font(Theme.mono(10.5))
                .foregroundStyle(Theme.listText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if isWorking(item.progress.phase) {
                if Snapshot.active {
                    // ImageRenderer does not draw the native indeterminate
                    // control correctly; the live window uses ProgressView.
                    Image(systemName: "hourglass")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 12, height: 12)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 12, height: 12)
                }
            }
            Text(stateText(item.progress.phase))
                .font(Theme.mono(9.5))
                .foregroundStyle(stateColor(item.progress.phase))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 6))
    }

    private func isWorking(_ phase: FinderArchiveProgressState.Phase) -> Bool {
        switch phase {
        case .waitingForHelper, .extracting:
            return true
        case .succeeded, .failed:
            return false
        }
    }

    private func stateText(_ phase: FinderArchiveProgressState.Phase) -> String {
        switch phase {
        case .waitingForHelper:
            return L10n.t(.archiveGettingHelper, lang)
        case .extracting:
            return L10n.t(.archiveUnpacking, lang)
        case .succeeded:
            return L10n.t(.archiveUnpacked, lang)
        case .failed(let failure):
            switch failure {
            case .helper:
                return L10n.t(.archiveHelperFailed, lang)
            case .tool:
                return L10n.t(.archiveFailed, lang)
            case .empty:
                return L10n.t(.archiveEmpty, lang)
            case .denied:
                return L10n.t(.archiveDenied, lang)
            }
        }
    }

    private func stateColor(_ phase: FinderArchiveProgressState.Phase) -> Color {
        switch phase {
        case .succeeded:
            return Theme.accentGreen
        case .failed:
            return Theme.accentRed
        case .waitingForHelper, .extracting:
            return Theme.textTertiary
        }
    }
}
