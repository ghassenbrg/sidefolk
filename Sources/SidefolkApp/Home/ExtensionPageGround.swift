import AppKit
import SidefolkCore
import SwiftUI

/// A dressed page's ground (D108): its colour for this appearance and, over it, a picture from its pack, whole or repeated. What
/// it is made of is decoration, so nothing here is read aloud. Without a dress, the app's own.
struct PageGround: View {
    var dress: PageDress?
    var model: ExtensionPageModel
    @Environment(\.colorScheme) private var scheme
    @State private var image: NSImage?

    var body: some View {
        if let dress, let color = Color(extensionHex: scheme == .dark ? dress.ground.dark : dress.ground.light) {
            ZStack(alignment: .top) {
                color
                if let image {
                    if dress.tile {
                        Image(nsImage: image).resizable(resizingMode: .tile)
                    } else {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).clipped()
                    }
                }
            }
            .accessibilityHidden(true)
            .task(id: "\(String(describing: dress.picture))\(scheme == .dark)") {
                guard let picture = dress.picture else { image = nil; return }
                image = await model.image(picture, dark: scheme == .dark, side: 1024)
            }
        } else {
            PageBackground()
        }
    }
}

extension View {
    /// Sidefolk's own question when a page asks for something the person must agree to (D106, D107): its words, never the extension's,
    /// beyond the purpose the install preview showed, labelled as that.
    func pageConsent(model: ExtensionPageModel) -> some View { modifier(PageConsentAsk(model: model)) }
}

private struct PageConsentAsk: ViewModifier {
    var model: ExtensionPageModel

    func body(content: Content) -> some View {
        content.alert(title, isPresented: Binding(get: { model.asking != nil }, set: { if !$0 { model.asking = nil } }), presenting: model.asking) { consent in
            Button(String(localized: "Allow", comment: "Letting an extension have the person's place or schedule reminders: the button")) {
                Task { await model.answer(consent, allow: true) }
            }
            Button(String(localized: "Not Now", comment: "Letting an extension have the person's place or schedule reminders: the button"), role: .cancel) {}
        } message: { consent in
            Text(verbatim: model.consentWords(consent))
        }
    }

    private var title: String {
        switch model.asking {
        case .place: String(localized: "Share your place with \(model.info.extensionName)?", comment: "Asked before an extension may read the person's place")
        case .schedule: String(localized: "Let \(model.info.extensionName) schedule reminders?", comment: "Asked before an extension may schedule reminders")
        case nil: ""
        }
    }
}
