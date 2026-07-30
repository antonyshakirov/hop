import HopCore
import SwiftUI

/// A reminder being edited. `date == nil` means "no reminder"; `repeatDays`
/// empty means one-shot.
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

/// The expanded form of one task row, shared by the to-do list and the tracker.
///
/// Shaped like a note, not like a form (Anton, 2026-07-28): the title is simply
/// the first line, a hairline separates it from the description, and both fields
/// take Return for a new line. Everything else is two small icons — a bell for
/// the reminder, a star for a favourite — so nothing needs a caption to explain
/// what it is.
struct TaskCardView: View {
    @Binding var draft: TaskCardDraft
    let lang: AppLanguage
    let onCommit: () -> Void
    let onCancel: () -> Void

    @FocusState private var titleFocused: Bool
    /// Which day the weekday row starts on: the user's setting, or the system's
    /// regional answer while it is on auto.
    @AppStorage(SettingsKey.firstWeekday) private var firstWeekdaySetting = FirstWeekday.auto

    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            title
            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)
                .padding(.top, 6)
                .padding(.bottom, 8)
            description
            controls
            if draft.reminder?.date != nil { repeatRow.padding(.top, 5) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.divider, lineWidth: 1))
        // Return belongs to the text now, so Escape is what abandons the edit —
        // the same key that cancels every other inline field in the panel.
        .onExitCommand(perform: onCancel)
    }

    // MARK: - Text

    /// The task itself, on the first line. No caption: a line at the top of a
    /// card is its title.
    ///
    /// A TextEditor rather than a TextField because on macOS a field treats
    /// Return as "submit" no matter what — the text simply refused to wrap
    /// (Anton, 2026-07-28). Here Return adds a line in both fields, the ✓ button
    /// or ⌘Return commits, and Escape abandons.
    private var title: some View {
        editor(text: $draft.text, font: Theme.mono(12), color: Theme.textPrimary,
               minHeight: 18, maxHeight: 64)
            .focused($titleFocused)
            .onAppear { if !Snapshot.active { titleFocused = true } }
    }

    private var description: some View {
        editor(text: $draft.note, font: Theme.mono(11), color: Theme.textSecondary,
               minHeight: 34, maxHeight: 120)
            .overlay(alignment: .topLeading) {
                // TextEditor has no placeholder of its own.
                if draft.note.isEmpty {
                    Text(t(.todoNotePlaceholder))
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textTertiary)
                        .allowsHitTesting(false)
                }
            }
    }

    /// A plain multi-line editor with the panel's own background — TextEditor
    /// brings a white sheet of its own, which has no place in the card.
    private func editor(text: Binding<String>, font: Font, color: Color,
                        minHeight: CGFloat, maxHeight: CGFloat) -> some View {
        TextEditor(text: text)
            .font(font)
            .foregroundStyle(color)
            .scrollContentBackground(.hidden)
            .background(.clear)
            .frame(minHeight: minHeight, maxHeight: maxHeight)
            .fixedSize(horizontal: false, vertical: true)
            // TextEditor insets its text by ~5pt; pull it back so both fields and
            // the icons below share one left edge.
            .padding(.leading, -5)
    }

    // MARK: - Controls

    /// Two groups that must not be mistaken for one: everything about the
    /// reminder on the LEFT (bell, day, time — and the weekday row directly
    /// under it), the favourite on the RIGHT, away from all of it. Sitting
    /// between the bell and the day chip, the star looked like part of the
    /// reminder (Anton, 2026-07-28).
    private var controls: some View {
        HStack(spacing: 8) {
            if draft.reminder != nil { bellButton }
            if draft.reminder?.date != nil {
                dayChip
                clockField(hourBinding, range: 0...23)
                Text(":")
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                clockField(minuteBinding, range: 0...59)
            }
            Spacer(minLength: 8)
            starButton
            FieldCommitButtons(onCommit: onCommit, onCancel: onCancel)
            // Return belongs to the text, so the keyboard commit is ⌘Return.
            Button("", action: onCommit)
                .keyboardShortcut(.return, modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
        }
        .padding(.top, 6)
    }

    /// The chip around a clock field: the panel's own field background, with the
    /// digits drawn by AppKit inside it. 34pt is enough for two digits — the old
    /// 44pt was sized for a three-digit setting field.
    private func clockField(_ value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        ClockField(value: value, range: range)
            .frame(width: 34, height: 24)
            .background(Theme.fieldBg, in: RoundedRectangle(cornerRadius: 5))
    }

    /// Arms a reminder at the next full hour, or clears the one that is set.
    private var bellButton: some View {
        let armed = draft.reminder?.date != nil
        return Button {
            if armed {
                draft.reminder?.date = nil
                draft.reminder?.repeatDays = []
            } else {
                setDay(offset: 0)
            }
        } label: {
            Image(systemName: armed ? "bell.fill" : "bell")
                .font(.system(size: 11))
                .foregroundStyle(armed ? Theme.textSecondary : Theme.textTertiary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverDim()
        .help(armed ? t(.todoRemindClear) : t(.todoRemindLabel))
    }

    private var starButton: some View {
        Button { draft.important.toggle() } label: {
            StarGlyph(color: draft.important ? Theme.textSecondary : Theme.textTertiary,
                      box: 10.5, filled: draft.important)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverDim()
        .help(t(.todoImportantLabel))
    }

    /// today / tomorrow / one of the next two weeks. A bordered chip, so it reads
    /// as something to press rather than as a label.
    private var dayChip: some View {
        Menu {
            Button(t(.todoRemindToday)) { setDay(offset: 0) }
            Button(t(.todoRemindTomorrow)) { setDay(offset: 1) }
            Divider()
            ForEach(2..<31, id: \.self) { offset in
                Button(Self.dayLabel(offset: offset)) { setDay(offset: offset) }
            }
        } label: {
            Text(dayChipTitle)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Theme.chipBg, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.controlStroke, lineWidth: 1))
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

    /// Picking a day keeps the time already typed; arming a reminder from nothing
    /// starts at the next full hour, which is what someone setting one usually
    /// means.
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
            // Round UP: the old "current hour + 1, clamped to 23" produced 23:00
            // at 23:40 — a reminder born already expired.
            let start = RemindSchedule.nextFullHour(after: Date(), calendar: calendar)
            let time = calendar.dateComponents([.hour, .minute], from: start)
            components.hour = time.hour
            components.minute = time.minute
        }
        if draft.reminder == nil { draft.reminder = ReminderDraft(date: nil, repeatDays: []) }
        draft.reminder?.date = calendar.date(from: components)
    }

    private var hourBinding: Binding<Int> { timeBinding(component: .hour, range: 0...23) }
    private var minuteBinding: Binding<Int> { timeBinding(component: .minute, range: 0...59) }

    private func timeBinding(component: Calendar.Component, range: ClosedRange<Int>) -> Binding<Int> {
        Binding(
            get: {
                guard let date = draft.reminder?.date else { return range.lowerBound }
                return Calendar.current.component(component, from: date)
            },
            set: { newValue in
                guard let date = draft.reminder?.date else { return }
                draft.reminder?.date = RemindSchedule.replacing(
                    component, with: min(max(newValue, range.lowerBound), range.upperBound),
                    in: date, calendar: .current)
            }
        )
    }

    // MARK: - Repeat

    /// Seven squares in the user's own week order — which day the week starts on
    /// follows the region and can be overridden in settings.
    private var repeatRow: some View {
        HStack(spacing: 4) {
            // A word, not a glyph: an icon here read as one more button, and
            // without anything the squares were a mystery (Anton, 2026-07-28).
            Text(t(.todoRepeatLabel))
                .font(Theme.mono(9))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize()
                .padding(.trailing, 6)
            ForEach(firstWeekdaySetting.weekOrder, id: \.self) { weekday in
                weekdaySquare(weekday)
            }
            Spacer(minLength: 0)
        }
    }

    private func weekdaySquare(_ weekday: Int) -> some View {
        let on = draft.reminder?.repeatDays.contains(weekday) ?? false
        return Button { toggleWeekday(weekday) } label: {
            Text(FirstWeekday.initial(for: weekday))
                .font(Theme.mono(9, weight: .semibold))
                .foregroundStyle(on ? Theme.background : Theme.textTertiary)
                .frame(width: 18, height: 18)
                .background(on ? Theme.textSecondary : Theme.fieldBg,
                            in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .stroke(on ? .clear : Theme.controlStroke, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(t(.todoRepeatLabel))
        .hoverDim()
    }

    private func toggleWeekday(_ weekday: Int) {
        guard var reminder = draft.reminder else { return }
        var days = Set(reminder.repeatDays)
        if days.contains(weekday) { days.remove(weekday) } else { days.insert(weekday) }
        reminder.repeatDays = TodoItem.normalizedWeekdays(Array(days))
        draft.reminder = reminder
    }
}
