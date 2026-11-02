import SidefolkCore
import SwiftUI

/// What stands in for an extension whose copy was made for an older Sidefolk (D101): it doesn't run, nothing of it is lost, and
/// the way on is one button. Its page, for someone who came to it from the sidebar.
struct ExtensionNeedsUpdateView: View {
    var info: ExtensionPageInfo
    var updates: UpdateModel

    var body: some View {
        VStack(spacing: Theme.Space.m) {
            EmptyState(title: Text(verbatim: info.title), message: Text(ExtensionNeedsUpdateWords.detail), systemImage: info.symbol ?? "puzzlepiece.extension")
            ExtensionNeedsUpdateButton(id: info.extensionId, name: info.extensionName, updates: updates, size: .regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum ExtensionNeedsUpdateWords {
    static let detail = String(localized: "This copy was made for an older Sidefolk. What you keep in it is safe, and comes back with the update.",
                               comment: "An extension that needs updating before it runs again: its row and its page")
    static let none = String(localized: "The gallery has no newer version yet.", comment: "An extension that needs updating, when no update exists yet")
}

/// “Update Name”, its progress, or why it can't yet. It takes the gallery's newest whichever channel the person follows: this copy doesn't run until then.
struct ExtensionNeedsUpdateButton: View {
    var id: String
    var name: String
    var updates: UpdateModel
    var size: SFButtonStyle.Size = .small

    var body: some View {
        switch updates.addonSteps[id] {
        case .updating?:
            HStack(spacing: Theme.Space.xs) {
                ProgressView().controlSize(.small)
                Text("Updating…", comment: "An add-on's update row while it installs").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
            .accessibilityElement(children: .combine)
        case .failed(let why)?:
            button.help(Text(verbatim: why))
        default:
            VStack(spacing: Theme.Space.xs) {
                button
                if updates.addonNoneYet.contains(id) {
                    Text(ExtensionNeedsUpdateWords.none).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                }
            }
        }
    }

    private var button: some View {
        Button { updates.addonActions?.updateOutOfDate(id) } label: {
            Text("Update \(name)", comment: "A button in the add-on gallery")
        }
        .buttonStyle(.sf(.primary, size: size))
        .disabled(updates.addonsBusy)
    }
}
