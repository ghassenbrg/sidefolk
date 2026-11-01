import SidefolkCore
import SwiftUI

/// "What changed" on a watch's detail page (D87): the lines of the two kept versions, inline or side by side. A change
/// is news, not a verdict (D78): what went is struck through in muted ink, what came sits on the news tint, and the −
/// and + say which is which, so neither side is red or green.
struct WatchChangeLines: View {
    var lines: [DiffLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in DiffLineView(line: line) }
        }
    }
}

struct WatchChangeColumns: View {
    var rows: [DiffRow]
    var beforeTitle: Text
    var afterTitle: Text

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Space.s) {
                beforeTitle.frame(maxWidth: .infinity, alignment: .leading)
                afterTitle.frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(Theme.Font.captionStrong).foregroundStyle(Theme.inkMuted)
            .padding(.bottom, Theme.Space.xs)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    if case .skipped(let n) = row.before {
                        DiffLineView(line: .skipped(n))
                    } else {
                        HStack(alignment: .top, spacing: Theme.Space.s) {
                            cell(row.before)
                            cell(row.after)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func cell(_ line: DiffLine?) -> some View {
        Group {
            if let line { DiffLineView(line: line) } else { Color.clear.frame(height: 1) }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// One line with its mark: − went, + came, nothing for a line both versions share; folded lines as a quiet count.
struct DiffLineView: View {
    var line: DiffLine

    var body: some View {
        switch line {
        case .same(let text): row(" ", text, ink: Theme.inkMuted, fill: .clear, said: String(localized: "Unchanged: \(text)"))
        case .removed(let text):
            row("−", text, ink: Theme.inkMuted, fill: Theme.well, strike: true, said: String(localized: "Removed: \(text)", comment: "A line that went from a watched page or file"))
        case .added(let text):
            row("+", text, ink: Theme.ink, fill: Theme.accentSoft, mark: Theme.link, said: String(localized: "Added: \(text)", comment: "A line that came to a watched page or file"))
        case .skipped(let n):
            HStack(spacing: Theme.Space.s) {
                Rectangle().fill(Theme.line).frame(height: 1)
                Text("\(n) unchanged lines", comment: "Lines folded away between changes").font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
                    .fixedSize()
                Rectangle().fill(Theme.line).frame(height: 1)
            }
            .padding(.vertical, Theme.Space.xs)
        }
    }

    private func row(_ sign: String, _ text: String, ink: Color, fill: Color, mark: Color? = nil, strike: Bool = false, said: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
            Text(verbatim: sign).foregroundStyle(mark ?? ink).frame(width: 12).accessibilityHidden(true)
            Text(verbatim: text.isEmpty ? " " : text).foregroundStyle(ink).strikethrough(strike, color: Theme.inkFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .font(Theme.Font.mono)
        .padding(.horizontal, Theme.Space.xs)
        .padding(.vertical, 1)
        .background(fill, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: said))
    }
}
