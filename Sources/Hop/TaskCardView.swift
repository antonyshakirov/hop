import HopCore
import SwiftUI

/// A reminder being edited. `date == nil` means "no reminder", which is what the
/// ✕ in the card writes; `repeatDays` empty means one-shot.
struct ReminderDraft: Equatable {
    var date: Date?
    var repeatDays: [Int]
}

/// Everything one task card edits. The card owns a DRAFT copy so a cancelled
/// edit never touches the store, and the list underneath keeps rendering stored
/// values while the card is open.
struct TaskCardDraft: Equatable {
    var text: String
    var note: String
    var important: Bool
    /// nil for the tracker, which has no reminders (its time already means
    /// "how long I worked", and two different times in one row contradict).
    var reminder: ReminderDraft?

    init(text: String, note: String, important: Bool, reminder: ReminderDraft? = nil) {
        self.text = text
        self.note = note
        self.important = important
        self.reminder = reminder
    }
}

/// The expanded form of one task row, shared by the to-do list and the tracker:
/// the full text (wrapping, never truncated), a comment, the importance mark,
/// and — for to-dos — the reminder time and its repeat weekdays. Theme tokens
/// only; every focused field is gated on `Snapshot.active` so a screenshot render
/// never shows an editing field.
struct TaskCardView: View {
    @Binding var draft: TaskCardDraft
    let lang: AppLanguage
    let onCommit: () -> Void
    let onCancel: () -> Void

    @FocusState private var titleFocused: Bool

    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            title
            note
            if draft.reminder != nil {
                remindRow
                if draft.reminder?.date != nil { repeatRow }
            }
            importantRow
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                FieldCommitButtons(onCommit: onCommit, onCancel: onCancel)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(Theme.divider, lineWidth: 1)
        )
    }

    // MARK: - Text

    /// The full task text, wrapping over as many lines as it needs — the collapsed
    /// row is the only place a task is ever truncated.
    private var title: some View {
        TextField("", text: $draft.text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(Theme.mono(12))
            .foregroundStyle(Theme.textPrimary)
            .focused($titleFocused)
            .lineLimit(1...6)
            .onSubmit(onCommit)
            .onAppear { if !Snapshot.active { titleFocused = true } }
    }

    /// The comment. Grows to five lines and then scrolls inside itself, so one
    /// card can never swallow the panel.
    private var note: some View {
        TextField(t(.todoNotePlaceholder), text: $draft.note, axis: .vertical)
            .textFieldStyle(.plain)
            .font(Theme.mono(11))
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1...5)
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .background(Theme.fieldBg, in: RoundedRectangle(cornerRadius: 5))
    }

    // MARK: - Reminder

    private var remindRow: some View {
        HStack(spacing: 6) {
            label(t(.todoRemindLabel))
            dayChip
            if draft.reminder?.date != nil {
                NumericField(value: hourBinding, range: 0...23)
                Text(":")
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                NumericField(value: minuteBinding, range: 0...59)
            }
            Spacer(minLength: 0)
            if draft.reminder?.date != nil {
                Button { draft.reminder?.date = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textTertiary)
                .hoverDim()
                .help(t(.todoRemindClear))
            }
        }
    }

    /// today / tomorrow / one of the next two weeks. A menu rather than a system
    /// date picker: the picker brings its own typography and backing into a panel
    /// that has neither.
    private var dayChip: some View {
        Menu {
            Button(t(.todoRemindToday)) { setDay(offset: 0) }
            Button(t(.todoRemindTomorrow)) { setDay(offset: 1) }
            Divider()
            ForEach(2..<15, id: \.self) { offset in
                Button(Self.dayLabel(offset: offset)) { setDay(offset: offset) }
            }
        } label: {
            Text(dayChipTitle)
                .font(Theme.mono(11))
                .foregroundStyle(draft.reminder?.date == nil ? Theme.textTertiary : Theme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Theme.chipBg, in: RoundedRectangle(cornerRadius: 5))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var dayChipTitle: String {
        guard let date = draft.reminder?.date else { return t(.todoRemindPickDate) }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return t(.todoRemindToday) }
        if calendar.isDateInTomorrow(date) { return t(.todoRemindTomorrow) }
        return Self.shortDate.string(from: date)
    }

    private static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter
    }()

    private static func dayLabel(offset: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        return shortDate.string(from: date)
    }

    /// Picking a day keeps the time already typed; a first pick starts at the next
    /// full hour, which is what someone setting a reminder usually means.
    private func setDay(offset: Int) {
        let calendar = Calendar.current
        let base = calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        let existing = draft.reminder?.date
        var components = calendar.dateComponents([.year, .month, .day], from: base)
        if let existing {
            let time = calendar.dateComponents([.hour, .minute], from: existing)
            components.hour = time.hour
            components.minute = time.minute
        } else {
            components.hour = min(23, calendar.component(.hour, from: Date()) + 1)
            components.minute = 0
        }
        draft.reminder?.date = calendar.date(from: components)
    }

    private var hourBinding: Binding<Int> {
        timeBinding(component: .hour, range: 0...23)
    }

    private var minuteBinding: Binding<Int> {
        timeBinding(component: .minute, range: 0...59)
    }

    private func timeBinding(component: Calendar.Component, range: ClosedRange<Int>) -> Binding<Int> {
        Binding(
            get: {
                guard let date = draft.reminder?.date else { return range.lowerBound }
                return Calendar.current.component(component, from: date)
            },
            set: { newValue in
                guard let date = draft.reminder?.date else { return }
                draft.reminder?.date = Calendar.current.date(
                    bySetting: component, value: min(max(newValue, range.lowerBound), range.upperBound),
                    of: date) ?? date
            }
        )
    }

    // MARK: - Repeat

    private var repeatRow: some View {
        HStack(spacing: 4) {
            label(t(.todoRepeatLabel))
            ForEach(Self.weekOrder, id: \.self) { weekday in
                weekdaySquare(weekday)
            }
            Spacer(minLength: 0)
        }
    }

    private func weekdaySquare(_ weekday: Int) -> some View {
        let on = draft.reminder?.repeatDays.contains(weekday) ?? false
        return Button { toggleWeekday(weekday) } label: {
            Text(Self.initial(for: weekday))
                .font(Theme.mono(9, weight: .semibold))
                .foregroundStyle(on ? Theme.background : Theme.textTertiary)
                .frame(width: 18, height: 18)
                .background(on ? Theme.textSecondary : Theme.fieldBg,
                            in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverDim()
    }

    private func toggleWeekday(_ weekday: Int) {
        guard var reminder = draft.reminder else { return }
        var days = Set(reminder.repeatDays)
        if days.contains(weekday) { days.remove(weekday) } else { days.insert(weekday) }
        reminder.repeatDays = TodoItem.normalizedWeekdays(Array(days))
        draft.reminder = reminder
    }

    /// The week in the user's own order — a locale that starts on Monday must not
    /// be shown a Sunday-first row.
    private static var weekOrder: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    private static func initial(for weekday: Int) -> String {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        return symbols[(weekday - 1) % symbols.count]
    }

    // MARK: - Importance

    private var importantRow: some View {
        HStack(spacing: 6) {
            label(t(.todoImportantLabel))
            Spacer(minLength: 0)
            Theme.MiniSwitch(isOn: $draft.important, tint: Theme.accentOrange)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(Theme.mono(10, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
            .frame(width: 58, alignment: .leading)
    }
}
