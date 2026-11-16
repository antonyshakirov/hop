import HopCore
import HopHardwareKit
import SwiftUI

// SPEC: docs/spec.md — Protected lid sessions, contextual failures.
struct AwakeLidFailureView: View {
    let reason: HardwareReason
    let lang: AppLanguage

    var body: some View {
        Text(HangingWords.glued(L10n.t(CoolingCopy.key(reason), lang),
            shortWords: L10n.shortWords(lang), trailing: L10n.trailingWords(lang)))
            .font(lang.isRTL ? .system(size: 10, weight: .medium) : Theme.mono(10))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
