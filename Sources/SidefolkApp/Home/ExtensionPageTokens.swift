import AppKit
import SidefolkCore
import SwiftUI

/// Words with values among them, each value a chip that moves and deletes as one (D125): the person sees "Today's plan", never the `{{plan}}` it stands for. What goes to
/// the tool is the plain text, values written as they came. Anything that isn't one of the field's own tokens stays plain text, so nothing typed can be lost.
struct TokenTextEditor: NSViewRepresentable {
    @Binding var text: String
    var tokens: [ExtensionPage.Field.Token]
    var label: String
    var multiline: Bool
    /// Bumped with a value to put at the caret.
    var inserting: (value: String, count: Int)
    var ended: () -> Void
    @Binding var focused: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = multiline
        scroll.borderType = .noBorder
        if let view = scroll.documentView as? NSTextView {
            view.delegate = context.coordinator
            view.drawsBackground = false
            view.isRichText = false
            view.importsGraphics = false
            view.allowsUndo = true
            view.isAutomaticQuoteSubstitutionEnabled = false
            view.isAutomaticDashSubstitutionEnabled = false
            view.font = .systemFont(ofSize: 13)
            view.textColor = .labelColor
            view.textContainerInset = NSSize(width: 4, height: 5)
            view.setAccessibilityLabel(label)
            context.coordinator.show(text, in: view)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        if context.coordinator.inserted != inserting.count {
            context.coordinator.inserted = inserting.count
            context.coordinator.insert(inserting.value, in: view)
        } else if context.coordinator.plain(view) != text, view.window?.firstResponder !== view {
            context.coordinator.show(text, in: view)
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TokenTextEditor
        var inserted = 0

        init(_ parent: TokenTextEditor) {
            self.parent = parent
            inserted = parent.inserting.count
        }

        /// The text with each value drawn as its chip.
        func show(_ text: String, in view: NSTextView) {
            view.textStorage?.setAttributedString(attributed(text))
        }

        private var base: [NSAttributedString.Key: Any] { [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor] }

        func attributed(_ text: String) -> NSAttributedString {
            let out = NSMutableAttributedString()
            var rest = Substring(text)
            while !rest.isEmpty {
                let next = parent.tokens.compactMap { token in rest.range(of: token.value).map { (token, $0) } }.min { $0.1.lowerBound < $1.1.lowerBound }
                guard let (token, range) = next else {
                    out.append(NSAttributedString(string: String(rest), attributes: base))
                    break
                }
                out.append(NSAttributedString(string: String(rest[..<range.lowerBound]), attributes: base))
                out.append(chip(token))
                rest = rest[range.upperBound...]
            }
            return out
        }

        private func chip(_ token: ExtensionPage.Field.Token) -> NSAttributedString {
            let attachment = TokenAttachment(value: token.value, label: token.label, symbol: token.symbol)
            let chip = NSMutableAttributedString(attachment: attachment)
            chip.addAttributes(base, range: NSRange(location: 0, length: chip.length))
            return chip
        }

        /// The plain text back: each chip as the value it stands for.
        func plain(_ view: NSTextView) -> String {
            guard let storage = view.textStorage else { return view.string }
            var out = ""
            storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attributes, range, _ in
                if let chip = attributes[.attachment] as? TokenAttachment {
                    out += chip.value
                } else {
                    out += (storage.string as NSString).substring(with: range)
                }
            }
            return out
        }

        func insert(_ value: String, in view: NSTextView) {
            guard let token = parent.tokens.first(where: { $0.value == value }) else { return }
            view.window?.makeFirstResponder(view)
            view.insertText(chip(token), replacementRange: view.selectedRange())
            parent.text = plain(view)
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = plain(view)
        }

        func textDidBeginEditing(_ notification: Notification) { parent.focused = true }

        func textDidEndEditing(_ notification: Notification) {
            parent.focused = false
            parent.ended()
        }

        func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard !parent.multiline, selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            view.window?.makeFirstResponder(nil)
            return true
        }
    }
}

/// A value drawn as a rounded chip with its symbol, in whichever appearance it's drawn in.
nonisolated final class TokenAttachment: NSTextAttachment, @unchecked Sendable {
    let value: String
    let label: String

    init(value: String, label: String, symbol: String?) {
        self.value = value
        self.label = label
        super.init(data: nil, ofType: nil)
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let words = NSAttributedString(string: label, attributes: [.font: font])
        let glyph = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 11, weight: .medium)) }
        let lead: CGFloat = glyph == nil ? 8 : 26
        let size = NSSize(width: ceil(words.size().width) + lead + 8, height: 20)
        image = NSImage(size: size, flipped: false) { rect in
            NSColor.controlAccentColor.withAlphaComponent(0).set()
            let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            NSColor.labelColor.withAlphaComponent(0.09).setFill()
            shape.fill()
            if let glyph {
                let tinted = NSImage(size: glyph.size, flipped: false) { r in
                    glyph.draw(in: r)
                    NSColor.labelColor.set()
                    r.fill(using: .sourceAtop)
                    return true
                }
                tinted.draw(in: NSRect(x: 8, y: (rect.height - glyph.size.height) / 2, width: glyph.size.width, height: glyph.size.height))
            }
            NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: NSColor.labelColor]).draw(at: NSPoint(x: lead, y: (rect.height - words.size().height) / 2))
            return true
        }
        bounds = NSRect(x: 0, y: -5, width: size.width, height: size.height)
    }

    required init?(coder: NSCoder) { nil }
}
