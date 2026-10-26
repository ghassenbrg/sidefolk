import AppKit
import SidefolkCore
import SwiftUI

/// Sidefolk's About window: the family and the wordmark at a size that does them justice, the
/// version and the line the brand stands on (D33). Replaces the standard panel, which could only
/// show the app icon.
struct AboutView: View {
    var body: some View {
        VStack(spacing: Theme.Space.m) {
            if let family = BrandAsset.familyColor.image {
                Image(nsImage: family).resizable().scaledToFit().frame(height: 150)
                    .accessibilityHidden(true)
            }
            Wordmark(height: 44)
                .padding(.top, -Theme.Space.xs)
            Text("Version \(Self.version)").font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
            VStack(spacing: Theme.Space.xs) {
                Text("Your AI sidekicks, always here.").font(Theme.Font.heading).foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("A companion that remembers, reminds, watches, and works with your agents.")
                    .font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, Theme.Space.s)
            Spacer(minLength: Theme.Space.s)
            if let notices = Self.notices {
                Button("Third-party notices") { NSWorkspace.shared.open(notices) }
                    .buttonStyle(.sf(.plain))
            }
            if let copyright = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String {
                Text(verbatim: copyright).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
            }
        }
        .padding(.horizontal, Theme.Space.xxl)
        .padding(.top, Theme.Space.xxl + Theme.Space.s)
        .padding(.bottom, Theme.Space.l)
        .frame(width: 380, height: 470)
        .background(Theme.surface)
    }

    /// "1.0.0 (212)": the marketing version and, inside an app bundle, its build.
    static var version: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(SidefolkVersion.current) (\($0))" } ?? SidefolkVersion.current
    }

    /// The bundled notices file; absent in a plain `swift run`, where the button is left out.
    static var notices: URL? {
        ResourceLocator.resources.map { $0.appendingPathComponent("THIRD_PARTY_NOTICES.md") }
            .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }
}

/// Owns the About window. Create one and keep it; `show` reuses the window.
@MainActor
final class AboutWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        WindowActivation.show(window)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow()
        Self.configure(window)
        window.delegate = self
        window.center()
        return window
    }

    /// Everything about the window except where it sits. UISnapshots uses this too.
    static func configure(_ window: NSWindow) {
        window.contentViewController = NSHostingController(rootView: AboutView())
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.title = String(localized: "About Sidefolk")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(Theme.surface)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
    }

    func windowWillClose(_ notification: Notification) {
        if let window { WindowActivation.closed(window) }
    }
}
