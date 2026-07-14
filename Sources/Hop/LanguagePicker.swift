import SwiftUI

/// Language dropdown with search. Matches the native name, the English
/// name and the code ("Russia" finds the Russian entry), but the list shows
/// only the native name — no codes or translations.
struct LanguagePicker: View {
    @Binding var selection: String
    @State private var open = false
    @State private var query = ""

    private var current: AppLanguage { L10n.resolve(selection) }

    /// "system (English)": the word is in the system language, parentheses say which one it is.
    private var autoTitle: String {
        "\(L10n.t(.languageAuto, .system)) (\(AppLanguage.system.nativeName))"
    }

    var body: some View {
        Button {
            query = ""
            open.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(selection == "auto" ? autoTitle : current.nativeName)
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverDim()
        .popover(isPresented: $open, arrowEdge: .bottom) {
            panel
        }
    }

    private var filtered: [AppLanguage] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return AppLanguage.pickerOrder }
        return AppLanguage.pickerOrder.filter {
            $0.nativeName.lowercased().contains(q)
                || $0.englishName.lowercased().contains(q)
                || $0.rawValue == q
        }
    }

    private var panel: some View {
        VStack(spacing: 8) {
            TextField(L10n.t(.searchLabel, current), text: $query)
                .textFieldStyle(.plain)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Theme.fieldBg, in: RoundedRectangle(cornerRadius: 6))
            ScrollView(showsIndicators: false) {
                VStack(spacing: 1) {
                    if query.isEmpty {
                        row(raw: "auto", title: autoTitle)
                    }
                    ForEach(filtered) { language in
                        row(raw: language.rawValue, title: language.nativeName)
                    }
                }
            }
            .frame(height: 236)
        }
        .padding(10)
        .frame(width: 220)
        .background(Theme.panelBackground)
    }

    private func row(raw: String, title: String) -> some View {
        Button {
            selection = raw
            open = false
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(Theme.mono(11, weight: selection == raw ? .semibold : .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                if selection == raw {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(5)
    }
}
