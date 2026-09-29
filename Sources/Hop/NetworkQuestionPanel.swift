import AppKit
import HopCore
import SwiftUI

/// SPEC: docs/spec.md — "Network access", questions.
@MainActor
enum NetworkQuestionPanel {
    private static var panel: NSPanel?

    static func show(_ network: NetworkFilterController) {
        let panel = panel ?? make(network)
        Self.panel = panel
        place(panel)
        panel.orderFrontRegardless()
    }

    static func hide() {
        panel?.orderOut(nil)
    }

    private static func make(_ network: NetworkFilterController) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 150),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        let host = NSHostingView(rootView: NetworkQuestionCard(network: network, lang: L10n.current))
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        return panel
    }

    private static func place(_ panel: NSPanel) {
        guard let screen = NSScreen.main?.visibleFrame, let content = panel.contentView else { return }
        let size = content.fittingSize
        panel.setContentSize(size)
        panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 8, y: screen.maxY - size.height - 8))
    }
}

struct NetworkQuestionCard: View {
    @ObservedObject var network: NetworkFilterController
    let lang: AppLanguage
    @State private var wholeProgram = false

    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }

    var body: some View {
        Group {
            if let question = network.questions.first {
                card(question)
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
        }
        .padding(10)
    }

    private func card(_ question: NetworkSighting) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(nsImage: NetworkProgramLook.icon(question.app, question.path))
                    .resizable()
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NetworkProgramLook.name(question.app, question.path))
                        .font(Theme.mono(12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(question.host.map { "→ \($0) · \(question.address):\(question.port)" }
                         ?? "→ \(question.address):\(question.port)")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Button { wholeProgram.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: wholeProgram ? "checkmark.square.fill" : "square")
                        .font(.system(size: 12))
                        .foregroundStyle(wholeProgram ? Theme.textPrimary : Theme.textTertiary)
                    Text(t(.networkAskWholeProgram))
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(spacing: 8) {
                if network.questions.count > 1 {
                    Text(t(.networkAskMore).replacingOccurrences(of: "%d", with: "\(network.questions.count - 1)"))
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 8)
                choice(t(.networkBlock), tint: Theme.accentRed) {
                    network.answer(question, .deny, wholeProgram: wholeProgram)
                    wholeProgram = false
                }
                choice(t(.networkAllow), tint: Theme.accentGreen) {
                    network.answer(question, .allow, wholeProgram: wholeProgram)
                    wholeProgram = false
                }
            }
        }
        .padding(14)
        .frame(width: 360, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.isDark ? Color(white: 0.11) : Color.white)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.controlStroke.opacity(0.6)))
                .shadow(color: .black.opacity(Theme.isDark ? 0.55 : 0.18), radius: 14, y: 6)
        )
    }

    private func choice(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.mono(11, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverDim()
    }
}
