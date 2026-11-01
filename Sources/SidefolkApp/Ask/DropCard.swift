import AppKit
import SidefolkCore
import SwiftUI

extension Attachment {
    /// The words a result shows it came from: dropped text as itself (its label already wears quotes).
    var caption: String {
        if case .text = kind, let text { return text.trimmingCharacters(in: .whitespacesAndNewlines).clipped(60) }
        return label
    }

    /// What was dropped, as the drop card sorts it (D88).
    var dropKind: DropKind {
        switch kind {
        case .url: return .link
        case .text: return .text
        case .file(let url):
            var folder: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &folder) && folder.boolValue ? .folder : .file
        }
    }
}

/// The drop card (D88): something dropped on the companion, and four likely things to do with it in a 2×2 grid, each
/// with one plain line of what it does. The first is what Return does while nothing is typed; typing still asks about
/// the item, as a drop always did.
struct DropCard: View {
    var attachment: Attachment
    var choices: [DropChoice]
    var choose: (DropChoice) -> Void
    var openWith: (URL) -> Void

    var body: some View {
        Grid(horizontalSpacing: Theme.Space.s, verticalSpacing: Theme.Space.s) {
            ForEach(Array(stride(from: 0, to: choices.count, by: 2)), id: \.self) { row in
                GridRow {
                    ForEach(choices[row..<min(row + 2, choices.count)], id: \.self) { choice in
                        cell(choice, first: choice == choices.first)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("What to do with \(attachment.label)", comment: "VoiceOver: the drop card's four choices"))
    }

    @ViewBuilder private func cell(_ choice: DropChoice, first: Bool) -> some View {
        let words = Self.words(choice, kind: attachment.dropKind)
        if choice == .openWith, case .file(let file) = attachment.kind {
            Menu {
                ForEach(Self.apps(for: file), id: \.self) { app in
                    Button { openWith(app) } label: {
                        Label { Text(verbatim: FileManager.default.displayName(atPath: app.path)) } icon: {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                        }
                    }
                }
            } label: {
                DropChoiceLabel(symbol: Self.symbol(choice), title: words.title, detail: words.detail, first: first)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
        } else {
            Button { choose(choice) } label: {
                DropChoiceLabel(symbol: Self.symbol(choice, kind: attachment.dropKind), title: words.title, detail: words.detail, first: first)
            }
            .buttonStyle(.plain)
        }
    }

    /// The apps that open this file or folder, the default one first, as Finder's Open With has them.
    static func apps(for file: URL) -> [URL] {
        let all = NSWorkspace.shared.urlsForApplications(toOpen: file)
        let main = NSWorkspace.shared.urlForApplication(toOpen: file)
        return Array(([main].compactMap { $0 } + all.filter { $0 != main }).prefix(12))
    }

    static func symbol(_ choice: DropChoice, kind: DropKind = .file) -> String {
        switch choice {
        case .save: kind == .link ? "link.badge.plus" : "square.and.arrow.down"
        case .watch: "eye"
        case .ask: Theme.Symbol.say
        case .openWith: "arrow.up.forward.app"
        case .remind: "alarm"
        case .copy: "doc.on.doc"
        case .playOnTV: "tv"
        }
    }

    /// The choice's name and one plain line of what it does, by what was dropped.
    static func words(_ choice: DropChoice, kind: DropKind) -> (title: Text, detail: Text) {
        switch (choice, kind) {
        case (.save, .link):
            (Text("Save link", comment: "The drop card: keep a dropped link"),
             Text("Adds it to your Inbox.", comment: "The drop card: what Save link does"))
        case (.save, .text):
            (Text("Save as note"), Text("Keeps the text in your Inbox.", comment: "The drop card: what Save as note does"))
        case (.save, _):
            (Text("Save to notebook"), Text("Notes its name and where it is in your Inbox.", comment: "The drop card: what saving a dropped file does"))
        case (.watch, .link):
            (Text("Watch page", comment: "The drop card: watch a dropped link"),
             Text("Tells you when the page changes.", comment: "The drop card: what Watch page does"))
        case (.watch, .folder):
            (Text("Watch it", comment: "The drop card: watch a dropped file or folder"),
             Text("Tells you when a new file arrives.", comment: "The drop card: what watching a dropped folder does"))
        case (.watch, _):
            (Text("Watch it", comment: "The drop card: watch a dropped file or folder"),
             Text("Tells you when it changes.", comment: "The drop card: what watching a dropped file does"))
        case (.ask, .link):
            (Text("Ask", comment: "The drop card: ask about a dropped link or text"),
             Text("Type a question about the page below.", comment: "The drop card: what Ask does with a link"))
        case (.ask, .text):
            (Text("Ask", comment: "The drop card: ask about a dropped link or text"),
             Text("Type what to do with it below.", comment: "The drop card: what Ask does with dropped text"))
        case (.ask, _):
            (Text("Ask about it", comment: "The drop card: ask about a dropped file or folder"),
             Text("Type a question below. The AI is told where it is.", comment: "The drop card: what Ask about it does with a file"))
        case (.openWith, _):
            (Text("Open with…", comment: "The drop card: open a dropped file in an app"),
             Text("Opens it in an app you pick.", comment: "The drop card: what Open with… does"))
        case (.remind, .text):
            (Text("Remind me"), Text("Asks when, then reminds you of it.", comment: "The drop card: what Remind me does with text"))
        case (.remind, _):
            (Text("Remind me"), Text("Asks when, then reminds you to look at it.", comment: "The drop card: what Remind me does with a link"))
        case (.copy, _):
            (Text("Copy"), Text("Puts the text on the clipboard.", comment: "The drop card: what Copy does"))
        case (.playOnTV, _):
            (Text("Play on TV"), Text("Plays the video on your TV with Miraya.", comment: "The drop card: what Play on TV does; Miraya is an extension's name"))
        }
    }
}

/// One choice on the drop card: its symbol, its name and what it does; the first carries ↩ and the accent's soft fill.
private struct DropChoiceLabel: View {
    var symbol: String
    var title: Text
    var detail: Text
    var first: Bool
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(first ? Theme.link : Theme.inkMuted)
                title.font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(1)
                Spacer(minLength: 0)
                if first { KeyHint("↩") }
            }
            detail.font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Space.s + 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(first ? Theme.accentSoft : hovering ? Theme.well.opacity(0.8) : Theme.well,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .contrastEdge(radius: Theme.Radius.control)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(first ? Text("Return does this", comment: "VoiceOver: the drop card's first choice is what Return does") : Text(verbatim: ""))
    }
}
