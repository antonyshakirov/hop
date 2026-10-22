import HopCore
import SwiftUI

struct AppQuitStrings {
    let title: String
    let quitAll: String
    let quit: String
    let pin: String
    let unpin: String
    let cannotPin: String
    let documentNotice: String
    let empty: String
    let requested: String
    let refused: String
}

struct AppQuitView: View {
    @ObservedObject var controller: AppQuitController
    let strings: AppQuitStrings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(strings.title)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button(strings.quitAll) { controller.quitAllUnpinned() }
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.accentRed)
                    .padding(8)
                    .background(Theme.chipBg, in: RoundedRectangle(cornerRadius: 6))
                    .buttonStyle(.plain)
                    .hoverDim()
                    .disabled(controller.unpinnedCount == 0)
                    .accessibilityIdentifier("appQuit.quitAll")
            }
            Text(strings.documentNotice)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.docText)
                .fixedSize(horizontal: false, vertical: true)
            if controller.applications.isEmpty {
                Text(strings.empty)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(controller.applications) { application in row(application) }
            }
        }
        .onAppear { controller.refresh() }
    }

    private func row(_ application: AppQuitApplication) -> some View {
        let pinned = controller.isPinned(application)
        return HStack(spacing: 10) {
            Group {
                if let icon = controller.icon(for: application) {
                    Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "app").resizable().aspectRatio(contentMode: .fit)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(application.name)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let state = controller.requestStates[application.id] {
                    Text(state == .requested ? strings.requested : strings.refused)
                        .font(Theme.mono(9))
                        .foregroundStyle(state == .requested ? Theme.textTertiary : Theme.accentOrange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { controller.setPinned(!pinned, for: application.id) } label: {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .font(.system(size: 12))
                    .foregroundStyle(pinned ? Theme.accentYellow : Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Theme.chipBg, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .hoverDim()
            .disabled(application.pinIdentifier == nil)
            .help(application.pinIdentifier == nil ? strings.cannotPin : pinned ? strings.unpin : strings.pin)
            .accessibilityLabel("\(pinned ? strings.unpin : strings.pin): \(application.name)")
            .accessibilityIdentifier("appQuit.pin.\(application.id.processIdentifier)")
            Button(strings.quit) { controller.quit(application.id) }
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textSecondary)
                .padding(8)
                .background(Theme.chipBg, in: RoundedRectangle(cornerRadius: 6))
                .buttonStyle(.plain)
                .hoverDim()
                .disabled(pinned)
                .accessibilityLabel("\(strings.quit): \(application.name)")
                .accessibilityIdentifier("appQuit.quit.\(application.id.processIdentifier)")
        }
    }
}
