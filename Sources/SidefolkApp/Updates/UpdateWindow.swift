import AppKit
import SidefolkCore
import SwiftUI

/// The update window (D46): what a look found, the notes of a new version and the way through download,
/// checks and restart. Opened by "Check for Updates…", "Update to …" and the bubble's Update.
struct UpdateView: View {
    var model: UpdateModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(headline).font(Theme.Font.heading).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subline).font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            content
            Spacer(minLength: 0)
            buttons
        }
        .padding(Theme.Space.xl)
        .frame(width: 460, height: 380, alignment: .topLeading)
        .background(Theme.surface)
    }

    private var headline: String {
        switch model.phase {
        case .idle, .checking: String(localized: "Looking for a newer Sidefolk…")
        case .upToDate: String(localized: "Sidefolk is up to date")
        case .available(let o): String(localized: "Sidefolk \(o.version.shown) is ready", comment: "An update: “Sidefolk 0.1.0 snapshot 430 is ready”")
        case .ready(let o): String(localized: "Sidefolk \(o.version.shown) will install by itself", comment: "An update downloaded and checked, waiting to restart Sidefolk")
        case .downloading(let o, _, _), .verifying(let o), .installing(let o):
            String(localized: "Updating to Sidefolk \(o.version.shown)", comment: "An update in progress")
        case .restarting: String(localized: "Restarting Sidefolk…")
        case .downloaded: String(localized: "The new version is in your Downloads folder")
        case .failed: String(localized: "The update didn't finish")
        }
    }

    private var subline: String {
        switch model.phase {
        case .idle, .checking, .upToDate, .available:
            String(localized: "You have Sidefolk \(model.running).", comment: "The version that runs now")
        case .ready:
            String(localized: "It's downloaded and checked. Sidefolk restarts once you've been away for a few minutes, or the next time you quit it.")
        case .downloading(_, let received, let total):
            String(localized: "Downloading \(ByteCountFormatter.string(fromByteCount: received, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))…",
                   comment: "Download progress: “Downloading 12 MB of 24 MB…”")
        case .verifying: String(localized: "Checking that it is whole, signed and notarized…")
        case .installing: String(localized: "Putting it in place…")
        case .restarting: String(localized: "It opens again in a moment.")
        case .downloaded(_, _, let reason): reason.explanation
        case .failed(_, let error): error.description
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .checking, .idle, .verifying, .installing, .restarting:
            ProgressView().progressViewStyle(.linear).tint(Theme.accent)
        case .downloading(_, let received, let total):
            ProgressView(value: Double(received), total: Double(max(total, 1))).progressViewStyle(.linear).tint(Theme.accent)
        case .ready(let offer):
            notes(offer)
        case .available(let offer):
            notes(offer)
            if case .download(let reason) = model.plan {
                Label { Text(verbatim: Wording.sentences([reason.explanation, String(localized: "Its disk image goes to your Downloads folder.")])) }
                    icon: { Image(systemName: "arrow.down.circle") }
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
        case .downloaded:
            Text("Open it and drag Sidefolk to the Applications folder, replacing this one. Your notes, reminders and settings stay.")
                .font(Theme.Font.body).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        case .upToDate:
            Text(model.lastCheck.map { String(localized: "Looked \(TimeText.relative($0)).", comment: "When updates were last looked for: “Looked 2 minutes ago.”") } ?? "")
                .font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
        case .failed:
            EmptyView()
        }
    }

    private func notes(_ offer: UpdateOffer) -> some View {
        ScrollView {
            ReleaseNotesView(notes: offer.notes).padding(Theme.Space.m)
        }
        .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .frame(maxHeight: 170)
    }

    @ViewBuilder private var buttons: some View {
        let actions = model.actions
        HStack(spacing: Theme.Space.s) {
            switch model.phase {
            case .available(let offer):
                Button("Skip This Version") { actions?.skip(offer) }.buttonStyle(.sf(.plain))
                Spacer()
                Button("Later") { actions?.later() }.buttonStyle(.sf(.secondary)).keyboardShortcut(.cancelAction)
                Button(model.plan == .replace ? "Update and Restart" : "Download") { actions?.install(offer) }
                    .buttonStyle(.sf(.primary)).keyboardShortcut(.defaultAction)
            case .ready:
                Spacer()
                Button("Later") { actions?.later() }.buttonStyle(.sf(.secondary)).keyboardShortcut(.cancelAction)
                Button("Restart Now") { actions?.restartNow() }.buttonStyle(.sf(.primary)).keyboardShortcut(.defaultAction)
            case .checking, .downloading, .verifying:
                Spacer()
                Button("Cancel") { actions?.cancel() }.buttonStyle(.sf(.secondary)).keyboardShortcut(.cancelAction)
            case .installing, .restarting, .idle:
                Spacer()
            case .downloaded(_, let file, _):
                Spacer()
                Button("Close") { actions?.later() }.buttonStyle(.sf(.secondary)).keyboardShortcut(.cancelAction)
                Button("Show in Finder") { actions?.reveal(file) }.buttonStyle(.sf(.primary)).keyboardShortcut(.defaultAction)
            case .upToDate:
                Spacer()
                Button("OK") { actions?.later() }.buttonStyle(.sf(.primary)).keyboardShortcut(.defaultAction)
            case .failed(let offer, _):
                if let offer { Button("Release Page") { actions?.openPage(offer) }.buttonStyle(.sf(.plain)) }
                Spacer()
                Button("Close") { actions?.later() }.buttonStyle(.sf(.secondary)).keyboardShortcut(.cancelAction)
                Button("Try Again") { if let offer { actions?.install(offer) } else { actions?.checkNow() } }
                    .buttonStyle(.sf(.primary)).keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// A release's notes as GitHub shows the simple Markdown they're written in: headings, bullet lists and inline
/// marks (bold, code, links). Anything fancier reads as plain lines.
private struct ReleaseNotesView: View {
    var notes: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            let lines = notes.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if lines.isEmpty {
                Text("No notes came with this version.").foregroundStyle(Theme.inkMuted)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                if line.hasPrefix("#") {
                    Text(Self.inline(String(line.drop { $0 == "#" }))).font(Theme.Font.bodyStrong)
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        Text(verbatim: "•").foregroundStyle(Theme.inkMuted)
                        Text(Self.inline(String(line.dropFirst(2)))).fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(Self.inline(line)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(Theme.Font.body)
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    static func inline(_ text: String) -> AttributedString {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return (try? AttributedString(markdown: trimmed, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(trimmed)
    }
}

/// Owns the update window. `show` reuses it.
@MainActor
final class UpdateWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model: UpdateModel
    /// The window was closed by its own button: the same as Later (or Cancel while busy).
    var onClose: (() -> Void)?

    init(model: UpdateModel) {
        self.model = model
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        WindowActivation.show(window)
    }

    func close() {
        guard let window else { return }
        window.delegate = nil
        window.close()
        WindowActivation.closed(window)
        window.delegate = self
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow()
        Self.configure(window, model: model)
        window.delegate = self
        window.center()
        return window
    }

    /// Everything about the window except where it sits. UISnapshots uses this too.
    static func configure(_ window: NSWindow, model: UpdateModel) {
        window.contentViewController = NSHostingController(rootView: UpdateView(model: model))
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.title = String(localized: "Software Update")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(Theme.surface)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
    }

    func windowWillClose(_ notification: Notification) {
        if let window { WindowActivation.closed(window) }
        onClose?()
    }
}
