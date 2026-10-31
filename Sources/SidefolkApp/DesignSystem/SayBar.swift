import SwiftUI

/// The Say bar's shell (D84): a capsule with a sparkle in the companion's colour, the words, and a key hint at the
/// trailing end. 40 tall in Home's toolbar (at most 560 wide), 52 on the desktop. The same field is Ask's and the
/// Pocket's. What the words do (the understanding row, results) is the screen's; this is only the field.
struct SayBarField: View {
    enum Size { case home, desktop }

    @Binding var text: String
    var prompt: Text
    var size: Size = .home
    /// The companion's colour, for the sparkle.
    var tint: Color = Theme.link
    /// The key that brings it up, shown while it's empty ("⌘K").
    var hint: String? = "⌘K"
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        let height = size == .home ? Theme.Size.sayBarHome : Theme.Size.sayBarDesktop
        HStack(spacing: Theme.Space.s + 2) {
            Image(systemName: Theme.Symbol.say).font(.system(size: size == .home ? 14 : 17, weight: .medium)).foregroundStyle(tint)
                .accessibilityHidden(true)
            TextField(text: $text, prompt: prompt.foregroundStyle(Theme.inkFaint)) { prompt }
                .textFieldStyle(.plain)
                .font(size == .home ? .system(size: 15 * ThemeStore.shared.style.tokens.type.scale) : Theme.Font.input)
                .foregroundStyle(Theme.ink)
                .focused($focused)
                .onSubmit(onSubmit)
            if let hint, text.isEmpty { KeyHint(hint) }
        }
        .padding(.horizontal, size == .home ? Theme.Space.l : Theme.Space.l + 2)
        .frame(height: height)
        .frame(maxWidth: size == .home ? Theme.Size.sayBarHomeMaxWidth : nil)
        .background(Theme.surfaceRaised, in: Capsule())
        .overlay {
            Capsule().strokeBorder(focused ? Theme.accent : Theme.line, lineWidth: focused ? 2 : 1)
        }
        .animation(Theme.Motion.micro, value: focused)
    }
}

/// A key or chord on a small keycap: "⌘K", "↩", "⌥↩".
struct KeyHint: View {
    var keys: String

    init(_ keys: String) { self.keys = keys }

    var body: some View {
        Text(verbatim: keys)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.inkMuted)
            .padding(.horizontal, 5)
            .frame(minHeight: 18)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityHidden(true)
    }
}

/// What the Say bar understood, before Return (principle 4): one plain sentence, its parts as chips (kind, time, place,
/// "On this Mac, no AI" or "Uses Claude"), and what each key does. Words are the screen's, from the same parse that
/// runs them (`IntentPlan`).
struct UnderstandingRow<Chips: View>: View {
    struct Key: Identifiable {
        var keys: String
        var title: Text
        var id: String { keys }
    }

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
