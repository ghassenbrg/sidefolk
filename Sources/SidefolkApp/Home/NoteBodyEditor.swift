import AppKit
import SidefolkCore
import SwiftUI

/// A note's text, formatted as you write (D53): headings, bold, italic, strikethrough, code, links, bullets,
/// numbered lists, checklists and quotes. The text stays the small Markdown `NoteMarks` reads; its marks hide
/// except on the line being edited, a checklist's box is drawn and ticks on a click, and Return carries a list on.
struct NoteBodyEditor: NSViewRepresentable {
    @Binding var text: String
    var controller: NoteEditorController

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layout = NoteLayoutManager()
        layout.delegate = layout
        layout.palette = .init(accent: NSColor(Theme.accent), muted: NSColor(Theme.inkMuted), faint: NSColor(Theme.inkFaint))
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        let view = NoteTextView(frame: .zero, textContainer: container)
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable = true
        view.autoresizingMask = .width
        view.drawsBackground = false
        view.isRichText = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.textContainerInset = NSSize(width: 0, height: 2)
        view.typingAttributes = NoteStyler.base
        view.linkTextAttributes = [.foregroundColor: NSColor(Theme.link), .cursor: NSCursor.pointingHand]
        view.delegate = context.coordinator
        view.setAccessibilityLabel(String(localized: "Text"))
        view.string = text
        NoteStyler.style(storage, caretLine: nil)
        context.coordinator.view = view
        controller.view = view

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NoteTextView else { return }
        controller.view = view
        context.coordinator.text = $text
        // Only a change from outside (another item, an agent's edit) replaces what is shown.
        if view.string != text, !context.coordinator.editing {
            view.string = text
            NoteStyler.style(view.textStorage!, caretLine: nil)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var view: NoteTextView?
        var editing = false
        private var caretLine: NSRange?

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let view else { return }
            editing = true
            text.wrappedValue = view.string
            editing = false
            restyle(view)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view else { return }
            let line = (view.string as NSString).lineRange(for: NSRange(location: view.selectedRange().location, length: 0))
            guard line != caretLine else { return }
            restyle(view)
        }

        /// Marks show on the line being edited; the line it left hides them again.
        private func restyle(_ view: NoteTextView) {
            guard let storage = view.textStorage else { return }
            let ns = view.string as NSString
            let line = ns.lineRange(for: NSRange(location: min(view.selectedRange().location, ns.length), length: 0))
            NoteStyler.style(storage, caretLine: line)
            caretLine = line
        }
    }
}

/// What the formatting bar asks of the editor it sits over.
@MainActor @Observable
final class NoteEditorController {
    @ObservationIgnored weak var view: NoteTextView?

    func toggle(_ inline: NoteMarks.Inline) { view?.toggle(inline) }
    func set(_ block: NoteMarks.Block) { view?.set(block) }
    func link() { view?.insertLink() }
    func focus() { if let view { view.window?.makeFirstResponder(view) } }
}

// MARK: - Styling

enum NoteStyler {
    static let size: CGFloat = 13.5
    static var paragraph: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 3
        p.paragraphSpacing = 4
        return p
    }

    static var base: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor(Theme.ink), .paragraphStyle: paragraph]
    }

    /// Restyles every line; `caretLine` keeps its marks visible.
    static func style(_ storage: NSTextStorage, caretLine: NSRange?) {
        let ns = storage.string as NSString
        storage.beginEditing()
        storage.setAttributes(base, range: NSRange(location: 0, length: ns.length))
        var at = 0
        while at < ns.length {
            let range = ns.lineRange(for: NSRange(location: at, length: 0))
            styleLine(storage, range, text: ns.substring(with: range), editing: caretLine.map { NSIntersectionRange($0, range).length > 0 || $0.location == range.location } ?? false)
            at = range.location + range.length
        }
        storage.endEditing()
    }

    private static func styleLine(_ storage: NSTextStorage, _ range: NSRange, text: String, editing: Bool) {
        let content = text.trimmingCharacters(in: .newlines)
        let line = NoteMarks.line(content)
        let faint = NSColor(Theme.inkFaint)
        func at(_ r: NSRange) -> NSRange { NSRange(location: range.location + r.location, length: r.length) }
        let marker = NSRange(location: range.location, length: line.marker)
        let p = NSMutableParagraphStyle()
        p.setParagraphStyle(paragraph)

        switch line.block {
        case .heading(let level):
            let sizes: [CGFloat] = [22, 18, 15.5]
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: sizes[level - 1], weight: level == 1 ? .bold : .semibold), range: range)
            p.paragraphSpacingBefore = level == 1 ? 8 : 5
            hide(storage, marker, editing: editing, color: faint)
        case .bullet:
            storage.addAttributes([.noteBullet: true, .foregroundColor: NSColor.clear], range: NSRange(location: range.location + line.indent, length: 1))
            indent(p, line, storage, marker)
        case .numbered:
            storage.addAttribute(.foregroundColor, value: NSColor(Theme.inkMuted), range: marker)
            indent(p, line, storage, marker)
        case .check(let done):
            if let box = line.box {
                // "- " and "[ ]" become one drawn box; the box keeps its place so the text doesn't jump.
                storage.addAttributes([.noteBox: done, .foregroundColor: NSColor.clear], range: at(box))
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: NSRange(location: range.location + line.indent, length: 2))
            }
            if done {
                let body = NSRange(location: marker.location + marker.length, length: max(0, content.utf16.count - line.marker))
                storage.addAttributes([.foregroundColor: NSColor(Theme.inkMuted), .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                       .strikethroughColor: faint], range: body)
            }
            indent(p, line, storage, marker)
        case .quote:
            storage.addAttribute(.foregroundColor, value: NSColor(Theme.inkMuted), range: range)
            storage.addAttribute(.noteQuote, value: true, range: range)
            p.headIndent = 14
            p.firstLineHeadIndent = 14
            hide(storage, marker, editing: editing, color: faint)
        case .paragraph:
            break
        }
        storage.addAttribute(.paragraphStyle, value: p, range: range)

        let bodyStart = line.marker
        let body = (content as NSString).substring(from: min(bodyStart, (content as NSString).length))
        for span in NoteMarks.spans(in: body) {
            let r = NSRange(location: range.location + bodyStart + span.range.location, length: span.range.length)
            let font = storage.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont ?? NSFont.systemFont(ofSize: size)
            switch span.kind {
            case .bold: storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask), range: r)
            case .italic: storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask), range: r)
            case .strike: storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: NSColor(Theme.inkMuted)], range: r)
            case .code:
                storage.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular),
                                       .backgroundColor: NSColor(Theme.surfaceSunken)], range: r)
            case .link:
                if let url = NoteMarks.url(of: span, in: body) {
                    let label = NSRange(location: r.location + 1, length: span.markers[1].location - span.range.location - 1)
                    storage.addAttribute(.link, value: url, range: label)
                }
            }
            for m in span.markers {
                hide(storage, NSRange(location: range.location + bodyStart + m.location, length: m.length), editing: editing, color: faint)
            }
        }
    }

    /// A mark shows faintly on the line being edited and takes no room elsewhere.
    private static func hide(_ storage: NSTextStorage, _ r: NSRange, editing: Bool, color: NSColor) {
        guard r.length > 0 else { return }
        storage.addAttribute(.foregroundColor, value: color, range: r)
        if !editing { storage.addAttribute(.noteHidden, value: true, range: r) }
    }

    private static func indent(_ p: NSMutableParagraphStyle, _ line: NoteMarks.Line, _ storage: NSTextStorage, _ marker: NSRange) {
        // Wrapped lines of an item line up with its text, not its marker.
        let font = NSFont.systemFont(ofSize: size)
        let width = (storage.attributedSubstring(from: marker).string as NSString).size(withAttributes: [.font: font]).width
        p.headIndent = width
        p.firstLineHeadIndent = 0
    }
}

nonisolated extension NSAttributedString.Key {
    static let noteHidden = NSAttributedString.Key("sidefolk.noteHidden")
    static let noteBox = NSAttributedString.Key("sidefolk.noteBox")
    static let noteBullet = NSAttributedString.Key("sidefolk.noteBullet")
    static let noteQuote = NSAttributedString.Key("sidefolk.noteQuote")
}

// MARK: - Layout: hidden marks, boxes, bullets, quote bars

nonisolated final class NoteLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    /// The theme's colours, set by the editor that makes it (they follow light and dark by themselves).
    struct Palette {
        var accent = NSColor.systemTeal
        var muted = NSColor.secondaryLabelColor
        var faint = NSColor.tertiaryLabelColor
    }
    var palette = Palette()

    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties props: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes: UnsafePointer<Int>,
                       font: NSFont, forGlyphRange range: NSRange) -> Int {
        guard let storage = textStorage else { return 0 }
        var changed: [NSLayoutManager.GlyphProperty]?
        for i in 0..<range.length where storage.attribute(.noteHidden, at: characterIndexes[i], effectiveRange: nil) != nil {
            if changed == nil { changed = Array(UnsafeBufferPointer(start: props, count: range.length)) }
            changed![i] = .null
        }
        guard let changed else { return 0 }
        changed.withUnsafeBufferPointer { setGlyphs(glyphs, properties: $0.baseAddress!, characterIndexes: characterIndexes, font: font, forGlyphRange: range) }
        return range.length
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        drawMarks(glyphsToShow, at: origin)
    }

    private func drawMarks(_ glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, let container = textContainers.first else { return }
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.noteBox, in: chars) { value, range, _ in
            guard let done = value as? Bool, range.location >= 2 else { return }
            // The box is drawn over "- [ ]", which keeps its width but no ink.
            let marker = NSRange(location: range.location - 2, length: range.length + 2)
            var rect = boundingRect(forGlyphRange: glyphRange(forCharacterRange: marker, actualCharacterRange: nil), in: container)
            rect.origin.x += origin.x
            rect.origin.y += origin.y
            let side: CGFloat = 15
            let box = NSRect(x: rect.minX + 1, y: rect.midY - side / 2 - 1, width: side, height: side)
            let path = NSBezierPath(ovalIn: box.insetBy(dx: 0.75, dy: 0.75))
            if done {
                palette.accent.setFill()
                NSBezierPath(ovalIn: box).fill()
                let tick = NSBezierPath()
                tick.move(to: NSPoint(x: box.minX + 4, y: box.midY + 0.5))
                tick.line(to: NSPoint(x: box.minX + 6.6, y: box.midY + 3))
                tick.line(to: NSPoint(x: box.maxX - 3.8, y: box.midY - 2.8))
                tick.lineWidth = 1.8
                tick.lineCapStyle = .round
                tick.lineJoinStyle = .round
                NSColor.white.setStroke()
                tick.stroke()
            } else {
                palette.faint.setStroke()
                path.lineWidth = 1.5
                path.stroke()
            }
        }
        storage.enumerateAttribute(.noteBullet, in: chars) { value, range, _ in
            guard value != nil else { return }
            let rect = boundingRect(forGlyphRange: glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: container)
            let d: CGFloat = 5
            palette.muted.setFill()
            NSBezierPath(ovalIn: NSRect(x: origin.x + rect.midX - d / 2, y: origin.y + rect.midY - d / 2, width: d, height: d)).fill()
        }
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        drawQuoteBars(glyphsToShow, at: origin)
    }

    private func drawQuoteBars(_ glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, let container = textContainers.first else { return }
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.noteQuote, in: chars) { value, range, _ in
            guard value != nil else { return }
            let rect = boundingRect(forGlyphRange: glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: container)
            palette.accent.withAlphaComponent(0.6).setFill()
            NSBezierPath(roundedRect: NSRect(x: origin.x, y: origin.y + rect.minY + 1, width: 3, height: rect.height - 2), xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}

// MARK: - The text view

final class NoteTextView: NSTextView {
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = boxIndex(at: point) {
            tick(lineStart: (string as NSString).lineRange(for: NSRange(location: index, length: 0)).location)
            return
        }
        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let layout = layoutManager, let container = textContainer, let storage = textStorage else { return }
        storage.enumerateAttribute(.noteBox, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard value != nil else { return }
            var rect = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: NSRange(location: range.location - 2, length: 5),
                                                                         actualCharacterRange: nil), in: container)
            rect.origin.x += textContainerOrigin.x
            rect.origin.y += textContainerOrigin.y
            addCursorRect(rect, cursor: .pointingHand)
        }
    }

    /// The character index of a checklist box under `point`, if there is one ("- [ ]" counts as the box).
    private func boxIndex(at point: NSPoint) -> Int? {
        guard let layout = layoutManager, let container = textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let p = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyph = layout.glyphIndex(for: p, in: container, fractionOfDistanceThroughGlyph: &fraction)
        let index = layout.characterIndexForGlyph(at: glyph)
        let line = (string as NSString).lineRange(for: NSRange(location: min(index, storage.length - 1), length: 0))
        let marks = NoteMarks.line((string as NSString).substring(with: line).trimmingCharacters(in: .newlines))
        guard let box = marks.box else { return nil }
        let area = NSRange(location: line.location + marks.indent, length: box.location + box.length - marks.indent)
        guard NSLocationInRange(index, area) || index == area.location + area.length else { return nil }
        let rect = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: area, actualCharacterRange: nil), in: container)
        return rect.insetBy(dx: -3, dy: -2).contains(p) ? index : nil
    }

    private func tick(lineStart: Int) {
        guard let next = NoteMarks.toggledCheck(string, lineStart: lineStart) else { return }
        replace(NSRange(location: 0, length: (string as NSString).length), with: next, keeping: selectedRange())
    }

    // Return carries a list on; Return on an empty item ends the list.
    override func insertNewline(_ sender: Any?) {
        let ns = string as NSString
        let caret = selectedRange()
        let line = ns.lineRange(for: NSRange(location: caret.location, length: 0))
        let before = ns.substring(with: NSRange(location: line.location, length: caret.location - line.location))
        let lineText = ns.substring(with: line).trimmingCharacters(in: .newlines)
        guard caret.length == 0, let next = NoteMarks.continuation(of: lineText) else { return super.insertNewline(sender) }
        if next.isEmpty {
            let marker = NoteMarks.line(lineText).marker
            replace(NSRange(location: line.location, length: marker), with: "", keeping: NSRange(location: line.location, length: 0))
            return
        }
        // Splitting an item in the middle still starts the new one with its marker.
        guard before.utf16.count >= NoteMarks.line(lineText).marker else { return super.insertNewline(sender) }
        insertText("\n" + next, replacementRange: caret)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.modifierFlags.contains(.command) else { return super.performKeyEquivalent(with: event) }
        let shift = event.modifierFlags.contains(.shift)
        switch (event.charactersIgnoringModifiers?.lowercased(), shift) {
        case ("b", false): toggle(.bold)
        case ("i", false): toggle(.italic)
        case ("x", true): toggle(.strike)
        case ("k", false): insertLink()
        case ("l", true): set(.check(done: false))
        case ("8", true), ("*", true): set(.bullet)
        case ("7", true), ("&", true): set(.numbered(1))
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    /// Wraps the selection in the span's marks, or takes them off when it already has them.
    func toggle(_ kind: NoteMarks.Inline) {
        let mark = switch kind {
        case .bold: "**"
        case .italic: "*"
        case .strike: "~~"
        case .code: "`"
        case .link: ""
        }
        guard !mark.isEmpty else { return insertLink() }
        let ns = string as NSString
        let sel = selectedRange()
        let m = (mark as NSString).length
        if sel.location >= m, sel.location + sel.length + m <= ns.length,
           ns.substring(with: NSRange(location: sel.location - m, length: m)) == mark,
           ns.substring(with: NSRange(location: sel.location + sel.length, length: m)) == mark {
            let outer = NSRange(location: sel.location - m, length: sel.length + 2 * m)
            replace(outer, with: ns.substring(with: sel), keeping: NSRange(location: outer.location, length: sel.length))
            return
        }
        let inner = ns.substring(with: sel)
        replace(sel, with: mark + inner + mark, keeping: NSRange(location: sel.location + m, length: sel.length))
    }

    /// Sets (or clears) a block on every line the selection touches.
    func set(_ block: NoteMarks.Block) {
        let ns = string as NSString
        let lines = ns.lineRange(for: selectedRange())
        var number = 1
        let changed = ns.substring(with: lines).components(separatedBy: "\n").enumerated().map { i, line -> String in
            if case .numbered = block, i > 0, line.isEmpty { return line }
            let target: NoteMarks.Block = if case .numbered = block { .numbered(number) } else { block }
            number += 1
            return NoteMarks.setting(target, on: line)
        }.joined(separator: "\n")
        let end = lines.location + (changed as NSString).length - (ns.substring(with: lines).hasSuffix("\n") ? 1 : 0)
        replace(lines, with: changed, keeping: NSRange(location: max(lines.location, end), length: 0))
    }

    /// A `[label](https://)` around the selection, with the address selected to type over.
    func insertLink() {
        let ns = string as NSString
        let sel = selectedRange()
        let label = sel.length > 0 ? ns.substring(with: sel) : String(localized: "link", comment: "A new link's placeholder label in a note")
        let address = "https://"
        let inserted = "[\(label)](\(address))"
        replace(sel, with: inserted, keeping: NSRange(location: sel.location + (label as NSString).length + 3, length: (address as NSString).length))
    }

    /// One undoable change, then the selection put where the change leaves it.
    private func replace(_ range: NSRange, with text: String, keeping selection: NSRange) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
        let length = (string as NSString).length
        setSelectedRange(NSRange(location: min(selection.location, length), length: min(selection.length, length - min(selection.location, length))))
        window?.invalidateCursorRects(for: self)
    }
}
