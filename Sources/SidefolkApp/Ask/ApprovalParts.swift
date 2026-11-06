import SidefolkCore
import SwiftUI

/// Why a card asks after outside content (D71), in the tone the install sheet uses: calm when Sidefolk's own extension
/// acts on what Sidefolk's own extension returned, strong otherwise.
struct ApprovalReasonLine: View {
    var reason: ApprovalReason

    var body: some View {
        Label {
            Text(verbatim: reason.text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: reason.calm ? "info.circle" : "exclamationmark.triangle").accessibilityHidden(true)
        }
        .font(Theme.Font.caption).foregroundStyle(reason.calm ? Theme.inkMuted : Theme.danger)
    }
}

/// The whole request an extension's tool would receive, folded: the summary above says it in words (D71).
struct ExactRequest: View {
    var input: String
    @State private var open = false

    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            ScrollView {
                Text(verbatim: input).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 140)
            .padding(Theme.Space.s)
            .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 6))
        } label: {
            Text("Exact request", comment: "An approval card: shows the arguments exactly as the extension receives them")
                .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
        }
    }
}

/// Exactly what an approval is about: the verbatim command, the full address, the paths, the text to
/// read. Shown on the card, and again beside a skipped step in Now (D37).
struct ApprovalDetails: View {
    var details: ApprovalRequest.Details
    @State private var showDetails = false

    var body: some View {
        switch details {
        case .none:
            EmptyView()
        case .command(let command):
            DisclosureGroup(isExpanded: $showDetails) {
                Text(verbatim: command.hiddenShown).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    .padding(Theme.Space.s).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 6))
            } label: {
                Text("Exact command").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
            .onAppear { showDetails = true }
        case .url(let url):
            Text(verbatim: url.hiddenShown).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.inkMuted).lineLimit(2).textSelection(.enabled)
        case .paths(let paths):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(paths.prefix(5), id: \.self) { p in
                    Text(verbatim: FolderAccess.displayPath(p)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.inkMuted)
                        .lineLimit(1).truncationMode(.middle)
                }
                if paths.count > 5 { Text("and \(paths.count - 5) more").font(Theme.Font.caption).foregroundStyle(Theme.inkFaint) }
            }
        case .text(let text):
            ReadInFull(text: text)
        case .folderAccess(let folder, let write):
            let path = FolderAccess.displayPath(folder)
            (write ? Text("Read and change files in \(path)") : Text("Read files in \(path)"))
                .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
        }
    }
}

/// Text the person has to read in full (a plan, a skill's instructions), laid out by how it's written: a paragraph that ends in a colon and has "•" lines under it reads as a heading
/// and its rows. All of it, in order, nothing folded (T44): only the look changes.
private struct ReadInFull: View {
    var text: String
    /// How tall the whole text is, to say there is more below when it is taller than the box.
    @State private var height: CGFloat = 0
    private static let limit: CGFloat = 300

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                ForEach(Array(ApprovalText.parts(text).enumerated()), id: \.offset) { _, part in
                    if let heading = part.heading {
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(verbatim: heading).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                            ForEach(Array(part.rows.enumerated()), id: \.offset) { _, row in
                                Text(verbatim: row).font(Theme.Font.callout).foregroundStyle(Theme.ink)
                                    .padding(.horizontal, Theme.Space.s).padding(.vertical, Theme.Space.xs)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .continuous))
                            }
                        }
                    } else {
                        Text(verbatim: part.rows.joined()).font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { Color.clear.preference(key: ReadHeight.self, value: $0.size.height) })
        }
        .onPreferenceChange(ReadHeight.self) { height = $0 }
        .frame(maxHeight: Self.limit)
        // A card that runs on says so: a fade at the foot and a line, so nobody takes the end of the box for the end of the text.
        .overlay(alignment: .bottom) {
            if height > Self.limit {
                VStack(spacing: 0) {
                    LinearGradient(colors: [Theme.well.opacity(0), Theme.well], startPoint: .top, endPoint: .bottom).frame(height: 24)
                    Text("Scroll to read the rest", comment: "Under a long card the person has to read in full: there is more below")
                        .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).frame(maxWidth: .infinity).padding(.bottom, 2).background(Theme.well)
                }
                .allowsHitTesting(false)
            }
        }
    }
}

private struct ReadHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
