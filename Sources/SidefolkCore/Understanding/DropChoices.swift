import Foundation

/// What can be done with something dropped on the companion (D84): four likely choices by kind, the first one what
/// Return does. Each is a path that already exists (a note, a watch, Ask, a reminder, the clipboard, an app); the app shows
/// them as a card in Ask and runs them. Extensions add theirs from their manifests (`drops`, D100), after these.
public enum DropChoice: String, Sendable, CaseIterable {
    case save, watch, ask, openWith, remind, copy
}

public enum DropKind: Sendable, Equatable {
    case file, folder, link, text
}

public enum DropChoices {
    /// The most offers from extensions a card shows, so it stays a card.
    static let mostOffers = 3

    /// Sidefolk's own choices for this kind, the likeliest first. A link an extension offers something for gives up its
    /// reminder to look at it: the extension's offer takes its place. Anything else keeps its four, the offers after them.
    public static func choices(for kind: DropKind, offers: Int = 0) -> [DropChoice] {
        switch kind {
        case .file, .folder: [.save, .watch, .ask, .openWith]
        case .link: offers > 0 ? [.save, .watch, .ask] : [.save, .watch, .ask, .remind]
        case .text: [.save, .remind, .ask, .copy]
        }
    }

    /// What's on offer for dropped files: every file must fit, and several need an action that takes a list.
    public static func offers(forFiles files: [String], among drops: [ExtensionDropAction]) -> [ExtensionDropAction] {
        guard !files.isEmpty, files.count <= ExtensionOutputs.maxFiles else { return [] }
        // A link's name says nothing of what would be read: `holiday.jpg` can point at `passport.pdf`.
        guard !files.contains(where: isLink) else { return [] }
        let many = files.count > 1
        return Array(drops.filter { drop in (!many || drop.takesMany) && files.allSatisfy { drop.matches(kind: .file, value: $0) } }.prefix(mostOffers))
    }

    private static func isLink(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFLNK
    }

    /// A file's name for the card: one plain line, whatever the file was called.
    public static func shownName(_ path: String) -> String {
        // Isolated, so a file's name keeps its own order inside a sentence in any language.
        "\u{2068}" + ExtensionText.line((path as NSString).lastPathComponent, characters: 120) + "\u{2069}"
    }

    /// What extensions that are on offer for this: its kind, and a pattern for a link's address or a file's name.
    public static func offers(for kind: DropKind, value: String, among drops: [ExtensionDropAction]) -> [ExtensionDropAction] {
        Array(drops.filter { $0.matches(kind: kind.manifestKind, value: value) }.prefix(mostOffers))
    }
}

extension DropKind {
    var manifestKind: ExtensionManifest.DropMeta.Kind {
        switch self {
        case .file: .file
        case .folder: .folder
        case .link: .link
        case .text: .text
        }
    }
}
