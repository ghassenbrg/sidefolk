import SwiftUI

/// An AI answer as text, the same in the Ask panel and in Conversations: inline Markdown only (links shown, remote
/// images never loaded), selectable, and links that open only as web pages.
struct AnswerText: View {
    var text: String

    var body: some View {
        Text(markdown).font(Theme.Font.body).foregroundStyle(Theme.ink)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            // Anything else (file:, app schemes) is ignored.
            .environment(\.openURL, OpenURLAction { url in
                guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.user == nil else { return .discarded }
                return .systemAction
            })
    }

    private var markdown: AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

/// Copies text, and says so for a moment.
struct CopyButton: View {
    var text: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc").imageScale(.small)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.sf(.plain))
        .help(copied ? Text("Copied") : Text("Copy"))
        .accessibilityLabel(copied ? Text("Copied") : Text("Copy"))
    }
}
