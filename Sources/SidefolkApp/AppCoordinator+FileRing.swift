import AppKit
import SidefolkCore

/// The ring (D152), the page's way to the drop card, and stopping an extension's work on the person's files.
extension AppCoordinator {
    func installFileRing() {
        fileRing.choicesFor = { [weak self] files in
            guard let self else { return [] }
            // Files only, as the card's offers are: a folder has nothing to become here.
            guard let attachment = Attachment.files(files.map { URL(fileURLWithPath: $0) }), attachment.dropKind == .file else { return [] }
            return DropChoices.ringChoices(forFiles: files, among: self.runtime.extensions.shelf.drops)
        }
        fileRing.choose = { [weak self] choice, urls in
            guard let self, let attachment = Attachment.files(urls) else { return }
            self.perform(choice.offer, choosing: choice.item, with: attachment, in: self.ask)
            self.showAsk(focus: false)
        }
        fileRing.packPicture = { [weak self] path, id in await self?.packPicture(path, extensionId: id) }
        fileRing.say = { [weak self] words in
            guard let self else { return }
            self.ask.add(.info(words), caption: nil)
            self.showAsk(focus: false)
        }
        fileRing.apply(runtime.settings.current.fileRing)
    }

    func chooseFilesForCard() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { [weak self] answer in
            MainActor.assumeIsolated {
                guard answer == .OK, let files = Attachment.files(panel.urls) else { return }
                self?.companionReceived(files)
            }
        }
    }

    /// The working card's Stop: the program is ended, so nothing more happens, and what it was making never reaches the person's folder.
    func stopWork(_ file: WorkingFile, in model: AskModel) {
        model.stopped = file.path
        Task { await runtime.extensions.stopWork(extensionId: file.extensionId) }
    }
}
