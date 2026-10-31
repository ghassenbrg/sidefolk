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
            .animation(Theme.Motion.micro, value: focused)
    }
}
