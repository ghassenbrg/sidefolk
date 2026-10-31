import SidefolkCore
import SwiftUI

/// Said wherever all history can be deleted (here and Settings › Privacy), so both promise the same thing.
enum DeleteHistoryWords {
    static let message: LocalizedStringKey =
        "Every conversation with the AI is deleted from this Mac. Your notes, reminders and Activity stay. This can't be undone."
}

/// One line of a conversation: the person's words on the trailing side, the answers as text to read, the steps in
/// between as quiet lines.
struct LineView: View {
    var line: ConversationLine
    var avatar: NSImage? = nil
    var name = ""

    var body: some View {
        switch line.kind {
        case .request(let spoken, let attachment):
            HStack {
                Spacer(minLength: 80)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(verbatim: line.text).font(Theme.Font.body).foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.Space.m)
                        .padding(.vertical, Theme.Space.s)
                        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    HStack(spacing: 4) {
                        if let attachment { Label { Text(verbatim: attachment.clipped(40)) } icon: { Image(systemName: "paperclip") } }
                        if spoken { Image(systemName: "waveform").accessibilityLabel("Spoken") }
                        Text(TimeText.short(line.at))
                    }
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
                }
            }
            .accessibilityElement(children: .combine)
        case .reply:
            HStack(alignment: .top, spacing: Theme.Space.s + 2) {
                ReplyAvatar(image: avatar)
                VStack(alignment: .leading, spacing: 4) {
                    if !name.isEmpty { Text(verbatim: name).font(Theme.Font.captionStrong).foregroundStyle(Theme.inkMuted) }
                    AnswerText(text: line.text)
                    HStack(spacing: 4) {
                        Text(TimeText.short(line.at)).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
                        CopyButton(text: line.text)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .step(let done):
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: line.text).fixedSize(horizontal: false, vertical: true)
                    if let detail = line.detail {
                        Text(verbatim: detail).foregroundStyle(Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                    }
                }
            } icon: {
                Image(systemName: done ? "checkmark.circle" : "xmark.circle")
            }
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.inkMuted)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(done ? Text("Done: \(line.text)") : Text("Not done: \(line.text). \(line.detail ?? "")"))
        case .note(let failed):
            // Red only when the run broke; a stopped or unanswered one is plain information.
            Label {
                Text(verbatim: line.text).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: failed ? "exclamationmark.circle" : "stop.circle").foregroundStyle(failed ? Theme.danger : Theme.inkMuted)
            }
            .font(Theme.Font.caption)
        }
    }
}

/// The companion's round profile picture beside what it said (CompanionArt.avatar).
struct ReplyAvatar: View {
    var image: NSImage?

    var body: some View {
        if let image {
            Image(nsImage: image).resizable().frame(width: 30, height: 30).accessibilityHidden(true)
        }
    }
}

/// A way to a kept conversation from somewhere else in Home (D58): its request, or the label given, as a link.
struct ConversationLink: View {
    var conversation: ConversationSummary
    var label: Text?
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            Label {
                (label ?? Text(verbatim: conversation.title.clipped(80))).lineLimit(1)
            } icon: {
                Image(systemName: "bubble.left.and.bubble.right")
            }
            .font(Theme.Font.caption)
        }
        .buttonStyle(.sf(.plain))
        .help(Text(verbatim: conversation.title))
    }
}
