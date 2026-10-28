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
        case .available(let offer):
            notes(offer)
            if case .download(let reason) = model.plan {
                Label { Text(verbatim: reason.explanation + " " + String(localized: "Its disk image goes to your Downloads folder.")) }
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
            Text(Self.markdown(offer.notes.isEmpty ? String(localized: "No notes came with this version.") : offer.notes))
                .font(Theme.Font.body).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(Theme.Space.m)
        }
        .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .frame(maxHeight: 170)
    }

    /// Release notes are Markdown; lines stay lines.
    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
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
