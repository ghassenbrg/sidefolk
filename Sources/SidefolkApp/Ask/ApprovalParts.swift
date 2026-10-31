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
                Text(verbatim: command).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    .padding(Theme.Space.s).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 6))
            } label: {
                Text("Exact command").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
            .onAppear { showDetails = true }
        case .url(let url):
            Text(verbatim: url).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.inkMuted).lineLimit(2).textSelection(.enabled)
        case .paths(let paths):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(paths.prefix(5), id: \.self) { p in
                    Text(verbatim: FolderAccess.displayPath(p)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.inkMuted)
                        .lineLimit(1)
                }
                if paths.count > 5 { Text("and \(paths.count - 5) more").font(Theme.Font.caption).foregroundStyle(Theme.inkFaint) }
            }
        case .text(let text):
            ScrollView {
                Text(text).font(Theme.Font.caption).foregroundStyle(Theme.ink).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
            .padding(Theme.Space.s)
            .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 6))
        case .folderAccess(let folder, let write):
            let path = FolderAccess.displayPath(folder)
            (write ? Text("Read and change files in \(path)") : Text("Read files in \(path)"))
                .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
        }
    }
}
