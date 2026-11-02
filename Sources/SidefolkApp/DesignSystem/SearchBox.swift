import SwiftUI

/// A search field in the app's look (Lantern's field, D84): a well 28 tall with a magnifier, the words and a button that
/// clears them, no border until it has the keyboard. Escape clears the words; Return and ↓ hand the keyboard to the
/// results (`submit`).
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
                    .buttonStyle(.sfIcon(side: 22))
                    .foregroundStyle(Theme.inkFaint)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Space.s)
        .frame(minHeight: Theme.Size.field)
        .fieldChrome(focused: focus.wrappedValue == focusValue)
    }
}
