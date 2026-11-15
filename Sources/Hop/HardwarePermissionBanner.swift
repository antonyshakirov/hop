import SwiftUI

enum HardwarePermissionIssue: Equatable {
    case missing, approval, unavailable, connection

    var message: L10nKey {
        switch self {
        case .missing: return .hardwareInstallHint
        case .approval: return .hardwareApprovalHint
        case .unavailable: return .hardwareSignedRequired
        case .connection: return .hardwareConnection
        }
    }

    var action: L10nKey {
        switch self {
        case .missing: return .hardwareInstall
        case .approval: return .hardwareApprove
        case .unavailable, .connection: return .coolingTitle
        }
    }
}

struct HardwarePermissionBanner: View {
    let issue: HardwarePermissionIssue
    let lang: AppLanguage
    let action: () -> Void

    private var actionLabel: some View {
        Text(L10n.t(issue.action, lang))
            .font(Theme.mono(10, weight: .bold)).foregroundStyle(Theme.accentYellow)
            .fixedSize(horizontal: false, vertical: true).contentShape(Rectangle())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(Theme.accentYellow)
                Text(L10n.t(issue.message, lang))
                    .font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if Snapshot.active {
                actionLabel
            } else {
                Button(action: action) { actionLabel }
                    .buttonStyle(.plain).hoverDim()
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 9))
    }
}
