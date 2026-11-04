import AppKit
import KeyboardShortcuts
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
        fileRing.toCard = { [weak self] urls in
            guard let files = Attachment.files(urls) else { return }
            self?.companionReceived(files)
        }
        fileRing.choose = { [weak self] choice, urls in
            guard let self, let attachment = Attachment.files(urls) else { return }
            self.perform(choice.offer, choosing: choice.item, with: self.withWordsForAI(attachment), in: self.ask)
            self.showAsk(focus: false)
        }
        fileRing.packPicture = { [weak self] path, id in await self?.packPicture(path, extensionId: id) }
        fileRing.say = { [weak self] words in
            guard let self else { return }
            self.ask.add(.info(words), caption: nil)
            self.showAsk(focus: false)
        }
        fileRing.otherKeys = { [weak self] in
            (self?.palettes.current ?? []).compactMap { KeyboardShortcuts.getShortcut(for: PaletteController.shortcutName($0)) }
        }
        fileRing.apply(runtime.settings.current.fileRing)
        // Setting keys unregisters the old ones whichever shortcut held them too, so after any change each takes its own again.
        NotificationCenter.default.addObserver(forName: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reclaimShortcuts() }
        }
    }

    private func reclaimShortcuts() {
        // Only what each already has on: this turns nothing on that was off. Done after the library has finished with its change.
        Task { [weak self] in
            guard let self else { return }
            // The talk key first, as settings do: turning it off unregisters its keys, and Ask may hold them. Not before Ask's own keys are set up.
            self.applyVoiceKeys()
            if self.talkKeysInstalled { KeyboardShortcuts.enable(.ask) }
            self.refreshCardKeys()
            self.palettes.reclaimShortcuts()
            self.fileRing.apply(self.runtime.settings.current.fileRing)
        }
    }

    func fileRingConflict() -> String? {
        guard runtime.settings.current.fileRing.enabled else { return nil }
        return fileRing.conflict.map(CardShortcut.explanation)
    }

    func chooseFilesForCard() {
        #if DEBUG
        // The debug app's stand-in for the person, and no panel on their screen.
        if let chosen = PageFilePanel.choiceForTest { return Attachment.files([URL(fileURLWithPath: chosen)]).map(companionReceived) ?? () }
        if WindowActivation.quiet { return }
        #endif
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
        // A second press has nothing more to stop, and mustn't hold up the next use of these files.
        guard model.stopped != file.id else { return }
        model.stopped = file.id
        Task { await runtime.extensions.stopWork(extensionId: file.extensionId, files: file.files) }
    }
}
