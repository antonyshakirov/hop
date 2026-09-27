import AppKit
import HopCore
import SwiftUI

/// SPEC: docs/spec.md — "Sharing Hop".
enum HopShare {
    static func link(_ lang: AppLanguage) -> URL {
        URL(string: ProductLink.page(for: lang.rawValue))!
    }

    static func present(from view: NSView, _ lang: AppLanguage) {
        let picker = NSSharingServicePicker(items: [L10n.t(.shareMessage, lang), link(lang)])
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    static func copyLink(_ lang: AppLanguage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link(lang).absoluteString, forType: .string)
    }

    static func openRepository() {
        if let url = URL(string: ProductLink.repository) { NSWorkspace.shared.open(url) }
    }
}

final class ShareAnchor {
    weak var view: NSView?
}

private struct ShareAnchorView: NSViewRepresentable {
    let anchor: ShareAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    /// WORKAROUND: snapshots cannot draw an AppKit view and paint it as a
    /// placeholder, and the anchor has nothing to show anyway.
    func shareAnchor(_ anchor: ShareAnchor) -> some View {
        background { if !Snapshot.active { ShareAnchorView(anchor: anchor) } }
    }
}

struct ShareHopCard: View {
    let lang: AppLanguage
    @State private var copied = false
    @State private var anchor = ShareAnchor()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                    Text(L10n.t(.shareTitle, lang))
                        .font(Theme.mono(13, weight: .semibold))
                        .tracking(-0.5)
                        .foregroundStyle(Theme.textPrimary)
                }
                Text(L10n.t(.shareBody, lang))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { buttons }
                VStack(alignment: .leading, spacing: 6) { buttons }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chipBg, in: RoundedRectangle(cornerRadius: 8))
        // WORKAROUND: ViewThatFits builds the chips twice, so an anchor inside
        // them can land on the copy that is not on screen; the card anchors instead.
        .shareAnchor(anchor)
    }

    @ViewBuilder private var buttons: some View {
        chip("square.and.arrow.up", L10n.t(.shareButton, lang)) {
            if let view = anchor.view { HopShare.present(from: view, lang) }
        }
        chip(copied ? "checkmark" : "link", L10n.t(copied ? .shareCopied : .shareCopyLink, lang)) {
            HopShare.copyLink(lang)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        }
        chip("star", L10n.t(.shareStar, lang)) { HopShare.openRepository() }
    }

    private func chip(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10))
                Text(label)
                    .font(Theme.mono(10))
                    .fixedSize()
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.controlStroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverDim()
        .handCursor()
        .help(label)
    }
}
