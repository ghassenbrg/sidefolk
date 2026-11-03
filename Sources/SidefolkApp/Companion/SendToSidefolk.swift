import AppKit

/// Finder's "Send to Sidefolk" (D151): macOS hands over the selected files, as a drag does, and they arrive on the same drop card.
/// Nothing runs until the person chooses there, so another app sending files through this gets no further than a drag would.
@MainActor final class SendToSidefolk: NSObject {
    private let received: (Attachment) -> Void

    init(received: @escaping (Attachment) -> Void) {
        self.received = received
    }

    @objc func sendToSidefolk(_ pasteboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard let files = Attachment.files(urls) else {
            error.pointee = String(localized: "Select a file first.") as NSString
            return
        }
        received(files)
    }
}
