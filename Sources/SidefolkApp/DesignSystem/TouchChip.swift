import SidefolkCore
import SwiftUI

/// What something can touch, as a chip with a symbol (Lantern's "what it touches", D84): on the permission slip, an
/// install sheet's passport and a gallery card. What reaches the person's things or leaves the Mac is amber (worth a
/// look, D78); what stays inside is a plain well. Never red: red is for what was blocked or failed.
enum Touch: CaseIterable {
    case changesFiles, readsFiles, internet, privateData, clipboard, screen, microphone, program, apps, changesThings, ownData, readOnly, acts

    init(_ effect: ApprovalRequest.Effect) {
        switch effect {
        case .readsPrivateData: self = .privateData
        case .readsFiles: self = .readsFiles
        case .usesInternet: self = .internet
        case .opensApps: self = .apps
        case .usesExtension: self = .ownData
        case .changesFiles: self = .changesFiles
        case .runsPrograms: self = .program
        case .changesThings: self = .changesThings
        case .actsForYou: self = .acts
        }
    }

    var symbol: String {
        switch self {
        case .changesFiles: "doc"
        case .readsFiles: "doc.text.magnifyingglass"
        case .internet: "globe"
        case .privateData: "lock"
        case .clipboard: "doc.on.clipboard"
        case .screen: "rectangle.on.rectangle"
        case .microphone: "mic"
        case .program: "terminal"
        case .apps: "arrow.up.forward.app"
        case .changesThings: "slider.horizontal.3"
        case .acts: "point.3.connected.trianglepath.dotted"
        case .ownData: "shippingbox"
        case .readOnly: "eye"
        }
    }

    var title: Text {
        switch self {
        case .changesFiles: Text("Changes files", comment: "What an action touches, on a chip: it moves, renames or creates files")
        case .readsFiles: Text("Reads files", comment: "What an action touches, on a chip: it reads files in a shared folder")
        case .internet: Text("Internet", comment: "What an action touches, on a chip: it reaches a server")
        case .privateData: Text("Private data", comment: "What an action touches, on a chip: private data like Apple Notes")
        case .clipboard: Text("Your clipboard", comment: "What an action touches, on a chip")
        case .screen: Text("Your screen", comment: "What an action touches, on a chip: it records or shares the screen")
        case .microphone: Text("Microphone", comment: "What an action touches, on a chip")
        case .program: Text("Runs a program", comment: "What an action touches, on a chip")
        case .apps: Text("Opens an app", comment: "What an action touches, on a chip: a link, an email draft or another app")
        case .changesThings: Text("Changes settings", comment: "What an action touches, on a chip: a setting, a watcher or Sidefolk's data")
        case .acts: Text("Acts for you", comment: "What an action touches, on a chip: an extension may use tools for the person, without asking")
        case .ownData: Text("Its own data only", comment: "What an action touches, on a chip: an extension that reaches nothing beyond its folder")
        case .readOnly: Text("Read only", comment: "What an action touches, on a chip: it only reads")
        }
    }

    /// Amber when it reaches the person's things or leaves the Mac; a plain well when it stays inside.
    var tone: ChipTone {
        switch self {
        // A program can do anything its user can, so it is worth a look too (the mockup's grey was too calm).
        case .changesFiles, .internet, .privateData, .clipboard, .screen, .microphone, .program, .acts: .warning
        case .readsFiles, .apps, .changesThings, .ownData, .readOnly: .neutral
        }
    }
}

struct TouchChip: View {
    var touch: Touch

    init(_ touch: Touch) { self.touch = touch }

    var body: some View {
        Chip(text: touch.title, tone: touch.tone, systemImage: touch.symbol)
    }
}
