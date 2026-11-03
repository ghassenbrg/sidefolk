import SwiftUI

extension View {
    /// Lantern's field (D84): a well with the control's corner, no border until it has the keyboard, then a 2 pt
    /// accent ring; a problem draws a 1 pt danger border, and the words under it say what to do (`InlineError`).
    /// For a `.plain` text field, padded by the caller.
    func fieldChrome(focused: Bool, problem: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        return background(Theme.well, in: shape)
            .overlay {
                if focused {
                    shape.strokeBorder(Theme.accent, lineWidth: 2)
                } else if problem {
                    shape.strokeBorder(Theme.danger, lineWidth: 1)
                }
            }
            .contrastEdge(radius: Theme.Radius.control)
            .animation(Theme.Motion.micro, value: focused)
    }

    /// Under Increase Contrast, a filled shape without a border of its own gets one (a well, a soft card, a tile), so
    /// its edge doesn't rest on a difference of fills alone. Nothing changes otherwise.
    func contrastEdge(radius: CGFloat) -> some View { modifier(ContrastEdge(radius: radius)) }
}

private struct ContrastEdge: ViewModifier {
    var radius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.overlay {
            if contrast == .increased {
                RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.controlBorder, lineWidth: 1)
            }
        }
    }
}

/// A text or secure field dressed as Lantern's well (D84) that keeps its own focus for the ring, for a field that
/// doesn't move the keyboard itself: `.lanternField()` in place of `.textFieldStyle(.roundedBorder)`.
struct LanternField: ViewModifier {
    var problem = false
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .focused($focused)
            .padding(.horizontal, Theme.Space.s)
            .frame(minHeight: Theme.Size.field)
            .fieldChrome(focused: focused, problem: problem)
    }
}

extension View {
    func lanternField(problem: Bool = false) -> some View { modifier(LanternField(problem: problem)) }

    /// A field's hint in the theme's faint ink, drawn over a field whose own prompt is empty: macOS paints a TextField's
    /// `prompt` in its system grey whatever style it's given, 3.15:1 on white (D130). The field keeps its label for VoiceOver.
    func fieldHint(_ hint: Text, showing: Bool, alignment: Alignment = .leading) -> some View {
        overlay(alignment: alignment) {
            if showing {
                hint.foregroundStyle(Theme.inkFaint).lineLimit(1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}
