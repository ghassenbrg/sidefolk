import AppKit
import SidefolkCore

/// Finder's "Send to Sidefolk" (D151): macOS hands over the selected files, as a drag does, and they arrive on the same drop card.
/// Nothing runs until the person chooses there. Unlike a drag it needs no click, so it never takes the keyboard (`filesFromAnotherApp`).
@MainActor final class SendToSidefolk: NSObject {
    private let received: (Attachment) -> Bool

    init(received: @escaping (Attachment) -> Bool) {
        self.received = received
    }

    @objc func sendToSidefolk(_ pasteboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard urls.count <= ExtensionOutputs.maxFiles, let files = Attachment.files(urls) else {
            error.pointee = String(localized: "Select a file first, or fewer of them.") as NSString
            return
        }
        if !received(files) {
            error.pointee = String(localized: "Sidefolk is in the middle of something. Try again when that's done.") as NSString
        }
    }
}
