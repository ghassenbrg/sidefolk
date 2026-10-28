import SwiftUI

/// A search field in the app's look: a magnifier, the words, and a button that clears them. Escape clears them too;
/// Return and ↓ hand the keyboard to the results (`submit`).
struct SearchBox<Focus: Hashable>: View {
    @Binding var text: String
    var prompt: Text
    var focus: FocusState<Focus?>.Binding
    var focusValue: Focus
    var submit: () -> Void = {}

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkFaint).accessibilityHidden(true)
            TextField("Search", text: $text, prompt: prompt)
                .textFieldStyle(.plain)
                .font(Theme.Font.body)
                .focused(focus, equals: focusValue)
                .accessibilityLabel(prompt)
                .onSubmit(submit)
                .onKeyPress(.downArrow) { submit(); return .handled }
                .onExitCommand { text = "" }
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.inkFaint)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, 6)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.line))
    }
}
