import SidefolkCore
import SwiftUI

/// Where a time is set (the founder's ask): typing first ("tomorrow at 9"), with a calendar button beside it for
/// people who'd rather tick and click. Both meet in one value: picking writes the time into the field
/// (`WhenText.phrase`), and what the field's words mean is said back under it in the person's own words, from the same
/// parser that will read them (`WhenParser`). ⌘↓ opens the picker; Escape closes it.
struct WhenField<Focus: Hashable>: View {
    @Binding var text: String
    var prompt: Text
    var parser: WhenParser
    var focus: FocusState<Focus>.Binding
    var focusValue: Focus
    /// Said under an empty field ("Leave empty to keep Today 10:30"); nothing when nil.
    var emptyHint: Text?
    /// Off where a picker is already on show beside the field.
    var showsPicker = true
    var submit: () -> Void = {}
    @State private var picking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Theme.Space.xs) {
                TextField("When", text: $text, prompt: prompt)
                    .font(Theme.Font.body)
                    .focused(focus, equals: focusValue)
                    .onSubmit(submit)
                    .accessibilityLabel(Text("When"))
                    .accessibilityValue(Text(verbatim: reading.map(\.words) ?? text))
                if showsPicker { pickerButton }
            }
            hint
        }
    }

    private var pickerButton: some View {
        Button { picking.toggle() } label: {
            Image(systemName: "calendar").foregroundStyle(picking ? Theme.link : Theme.inkMuted)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.downArrow, modifiers: .command)
        .help(Text("Pick a date and time (⌘↓)"))
        .accessibilityLabel(Text("Pick a date and time"))
        .popover(isPresented: $picking, arrowEdge: .bottom) {
            WhenPicker(start: reading?.date, parser: parser) { picked in
                text = WhenText.phrase(for: picked, timeZone: parser.calendar.timeZone)
                picking = false
            }
        }
    }

    private var reading: WhenReading? { WhenReading(text, parser: parser) }

    @ViewBuilder private var hint: some View {
        if let reading {
            Label { Text(verbatim: reading.words) } icon: { Image(systemName: reading.past ? "exclamationmark.circle" : "checkmark") }
                .font(Theme.Font.caption)
                .foregroundStyle(reading.past ? Theme.danger : Theme.inkMuted)
                .lineLimit(1)
                .accessibilityHidden(true)
        } else if !text.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("Not a time I can read yet. Try “tomorrow 9:00”, or pick one.")
                .font(Theme.Font.caption).foregroundStyle(Theme.inkFaint).lineLimit(2)
        } else if let emptyHint {
            emptyHint.font(Theme.Font.caption).foregroundStyle(Theme.inkFaint).lineLimit(2)
        }
    }
}

extension WhenField where Focus == Bool {
    /// A field nothing else moves the keyboard to.
    init(text: Binding<String>, prompt: Text, parser: WhenParser, focus: FocusState<Bool>.Binding, emptyHint: Text? = nil,
         showsPicker: Bool = true, submit: @escaping () -> Void = {}) {
        self.init(text: text, prompt: prompt, parser: parser, focus: focus, focusValue: true, emptyHint: emptyHint,
                  showsPicker: showsPicker, submit: submit)
    }
}

/// What a when field's words mean, as the field says it back: "Tomorrow, 9:00 AM · every day", and whether that time
/// has already passed (it's refused then, as typed or picked).
struct WhenReading {
    var date: Date
    var words: String
    var past: Bool

    init?(_ text: String, parser: WhenParser, now: Date = Date()) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let found = parser.parse(trimmed, now: now) else { return nil }
        date = found.date
        past = found.date <= now
        // Today and Tomorrow by name; any other day with its date, so "Mon" is never the wrong Monday.
        let cal = parser.calendar
        let day = cal.isDate(found.date, inSameDayAs: now) || cal.isDate(found.date, inSameDayAs: now.addingTimeInterval(86400))
            ? TimeFormat.day(found.date, now: now, calendar: cal)
            : found.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        // The clock in the person's own 12 or 24 hours.
        var words = String(localized: "\(day), \(found.date.formatted(date: .omitted, time: .shortened))",
                           comment: "What a typed time means: “Tomorrow, 9:00 AM”")
        if let rule = found.recurrence { words += " · " + TimeFormat.recurrence(rule, calendar: parser.calendar) }
        if past { words += " · " + String(localized: "That time has already passed.") }
        self.words = words
    }
}

/// The classic way: a month to click a day in, the time, and a few usual times one click away. Set writes the time
/// into the field.
struct WhenPicker: View {
    var parser: WhenParser
    var choose: (Date) -> Void
    @State private var date: Date

    init(start: Date?, parser: WhenParser, choose: @escaping (Date) -> Void) {
        self.parser = parser
        self.choose = choose
        _date = State(initialValue: start.flatMap { $0 > Date() ? $0 : nil } ?? Self.nextHour(parser.calendar))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ButtonRow(spacing: 6) {
                ForEach(presets, id: \.label) { preset in
                    Button { date = preset.date } label: { Text(verbatim: preset.label) }
                        .buttonStyle(.sf(.secondary)).fixedSize()
                        .help(Text(verbatim: preset.date.formatted(date: .abbreviated, time: .shortened)))
                }
            }
            DatePicker("Day", selection: $date, in: Date()..., displayedComponents: [.date])
                .datePickerStyle(.graphical)
                .labelsHidden()
            HStack {
                DatePicker("Time", selection: $date, in: Date()..., displayedComponents: [.hourAndMinute])
                    .datePickerStyle(.stepperField)
                Spacer(minLength: Theme.Space.m)
                Button("Set") { choose(date) }
                    .buttonStyle(.sf(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(date <= Date())
            }
        }
        .padding(Theme.Space.m)
        .frame(width: 300)
    }

    /// The usual times that are still ahead, read by the same parser as typed words.
    private var presets: [(label: String, date: Date)] {
        let now = Date()
        let usual: [(String, String)] = [
            (String(localized: "In an hour"), "in an hour"),
            (String(localized: "This evening"), "this evening"),
            (String(localized: "Tomorrow morning"), "tomorrow morning"),
            (String(localized: "Next week", comment: "A quick time: next Monday morning"), "next monday"),
        ]
        return usual.compactMap { label, phrase in
            guard let found = parser.parse(phrase, now: now), found.confidence != .low, found.date > now else { return nil }
            if phrase == "this evening", !parser.calendar.isDate(found.date, inSameDayAs: now) { return nil }
            return (label, found.date)
        }
    }

    static func nextHour(_ calendar: Calendar, after now: Date = Date()) -> Date {
        let hour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        return calendar.date(byAdding: .hour, value: 1, to: hour) ?? now.addingTimeInterval(3600)
    }
}
