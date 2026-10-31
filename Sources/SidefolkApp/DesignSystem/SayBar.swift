import SwiftUI

/// The Say bar's shell (D84): a capsule with a sparkle in the companion's colour, the words, and a key hint at the
/// trailing end. 40 tall in Home's toolbar (at most 560 wide), 52 on the desktop. The same field is Ask's and the
/// Pocket's. What the words do (the understanding row, results) is the screen's; this is only the field.
struct SayBarField<Trailing: View>: View {
    enum Size { case home, desktop }

    @Binding var text: String
    var prompt: Text
    var size: Size = .home
    /// The companion's colour, for the sparkle.
    var tint: Color = Theme.link
    /// The key that brings it up, shown while it's empty ("⌘K").
    var hint: String? = "⌘K"
    /// The leading mark: the sparkle, or the screen's own ("waveform" while listening), animated while `active`.
    var symbol = Theme.Symbol.say
    var active = false
    /// Words may run to a few lines (Ask on the desktop) instead of one.
    var multiline = false
    /// The words can't be changed now (working, listening); the trailing controls stay usable.
    var disabled = false
    /// The screen's own focus, when it moves focus itself; otherwise the field keeps its own.
    var focus: FocusState<Bool>.Binding?
    var onSubmit: () -> Void = {}
    /// Return with ⌘ or ⌥ (ask the AI, save as a note): true when the screen used it.
    var onModifiedReturn: ((EventModifiers) -> Bool)?
    /// Bumped by the screen to give the field the keyboard (Home's ⌘K).
    var focusTrigger = 0
    /// Told when the field gets or loses the keyboard, so the screen can show what the words will do.
    var focusChanged: (Bool) -> Void = { _ in }
    /// Esc, while the field has the keyboard.
    var onEscape: (() -> Void)?
    /// At the trailing end: a microphone, Stop while working.
    @ViewBuilder var trailing: Trailing
    @FocusState private var focused: Bool

    var body: some View {
        let height = size == .home ? Theme.Size.sayBarHome : Theme.Size.sayBarDesktop
        let binding = focus ?? $focused
        HStack(alignment: multiline ? .firstTextBaseline : .center, spacing: Theme.Space.s + 2) {
            Image(systemName: symbol).font(.system(size: size == .home ? 14 : 17, weight: .medium)).foregroundStyle(tint)
                .symbolEffect(.variableColor.iterative, isActive: active)
                .accessibilityHidden(true)
            TextField(text: $text, prompt: prompt.foregroundStyle(Theme.inkFaint), axis: multiline ? .vertical : .horizontal) { prompt }
                .textFieldStyle(.plain)
                .font(size == .home ? .system(size: 15 * ThemeStore.shared.style.tokens.type.scale) : Theme.Font.input)
                .foregroundStyle(Theme.ink)
                .lineLimit(multiline ? 1...5 : 1...1)
                .focused(binding)
                // The field's own ring is the focus ring; AppKit's square one would show beside the rounded ends.
                .focusEffectDisabled()
                .disabled(disabled)
                .onSubmit(onSubmit)
                .onKeyPress(.return, phases: .down) { press in
                    guard let onModifiedReturn, !press.modifiers.intersection([.command, .option]).isEmpty else { return .ignored }
                    return onModifiedReturn(press.modifiers) ? .handled : .ignored
                }
                .onExitCommand { onEscape?() }
            if let hint, text.isEmpty { KeyHint(hint) }
            trailing
        }
        .padding(.horizontal, size == .home ? Theme.Space.l : Theme.Space.l + 2)
        .padding(.vertical, multiline ? (height - 22) / 2 : 0)
        .frame(minHeight: height)
        .frame(maxWidth: size == .home ? Theme.Size.sayBarHomeMaxWidth : .infinity)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: height / 2, style: .continuous))
        .overlay {
            // strokeBorder insets the shape by half the line; a radius past half the inset height draws flat ends
            // beside the round ones, so the radius shrinks with it.
            let ring: CGFloat = binding.wrappedValue ? 2 : 1
            RoundedRectangle(cornerRadius: height / 2 - ring / 2, style: .continuous)
                .strokeBorder(binding.wrappedValue ? Theme.accent : Theme.line, lineWidth: ring)
        }
        .animation(Theme.Motion.micro, value: binding.wrappedValue)
        .onChange(of: focusTrigger) { binding.wrappedValue = true }
        .onChange(of: binding.wrappedValue) { focusChanged(binding.wrappedValue) }
    }
}

extension SayBarField where Trailing == EmptyView {
    init(text: Binding<String>, prompt: Text, size: Size = .home, tint: Color = Theme.link, hint: String? = "⌘K",
         onSubmit: @escaping () -> Void = {}, focusTrigger: Int = 0, focusChanged: @escaping (Bool) -> Void = { _ in },
         onEscape: (() -> Void)? = nil) {
        self.init(text: text, prompt: prompt, size: size, tint: tint, hint: hint, onSubmit: onSubmit, focusTrigger: focusTrigger,
                  focusChanged: focusChanged, onEscape: onEscape) { EmptyView() }
    }
}

/// A key and what it does, under the Say bar ("↩ Do it", "⌘↩ Ask Claude").
struct UnderstandingKey: Identifiable {
    var keys: String
    var title: Text
    var id: String { keys }
}

/// A key or chord on a small keycap: "⌘K", "↩", "⌥↩".
struct KeyHint: View {
    var keys: String

    init(_ keys: String) { self.keys = keys }

    var body: some View {
        // Isolated left to right: a chord reads ⌘↩ in Arabic too (03-system › RTL: keys aren't mirrored).
        Text(verbatim: "\u{2066}\(keys)\u{2069}")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.inkMuted)
            .padding(.horizontal, 5)
            .frame(minHeight: 18)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// What the Say bar understood, before Return (principle 4): one plain sentence, its parts as chips (kind, time, place,
/// "On this Mac, no AI" or "Uses Claude"), and what each key does. Words are the screen's, from the same parse that
/// runs them (`IntentPlan`).
struct UnderstandingRow<Chips: View>: View {
    typealias Key = UnderstandingKey

    var symbol: String = "sparkle"
    var sentence: Text
    var keys: [Key] = []
    @ViewBuilder var chips: Chips

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Label { sentence.fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: symbol).foregroundStyle(Theme.inkFaint) }
                .font(Theme.Font.body)
                .foregroundStyle(Theme.ink)
            ButtonRow(spacing: Theme.Space.xs) { chips }
            if !keys.isEmpty {
                HStack(spacing: Theme.Space.m) {
                    ForEach(keys) { key in
                        HStack(spacing: 5) {
                            KeyHint(key.keys)
                            key.title.font(Theme.Font.callout).foregroundStyle(Theme.inkMuted)
                        }
                    }
                }
            }
        }
    }
}
