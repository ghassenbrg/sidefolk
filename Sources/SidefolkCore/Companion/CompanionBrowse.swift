import Foundation

/// What the gallery's companions are narrowed to and ordered by in Settings › Companion › Gallery (D77)
///: words, a look, who made them, whether to leave out those already here, and an order. Built for a
/// gallery of hundreds; each choice is offered only when the catalog has what it needs (Newest needs dates).
public struct CompanionBrowse: Equatable, Sendable {
    public enum Look: String, CaseIterable, Sendable { case any, threeD, twoD }
    public enum Maker: String, CaseIterable, Sendable { case anyone, sidefolk, others }
    public enum Sort: String, CaseIterable, Sendable { case name, newest, smallest }

    public var text = ""
    public var look = Look.any
    public var maker = Maker.anyone
    /// Leaves out the companions already on this Mac.
    public var hideOwned = false
    public var sort = Sort.name

    public init(text: String = "", look: Look = .any, maker: Maker = .anyone, hideOwned: Bool = false, sort: Sort = .name) {
        self.text = text
        self.look = look
        self.maker = maker
        self.hideOwned = hideOwned
        self.sort = sort
    }

    /// Whether anything but the order narrows the list: "Clear Filters" has something to clear.
    public var isNarrowed: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty || look != .any || maker != .anyone || hideOwned
    }

    /// The companions of `entries` this copy can wear that pass, in order. `owned` names the characters already here;
    /// `words` adds what else an entry is called (Sidefolk's own companions' lines in the person's language).
    public func apply(_ entries: [AddonEntry], owned: Set<String>, words: (AddonEntry) -> [String] = { _ in [] }) -> [AddonEntry] {
        let shown = entries.filter { entry in
            guard entry.wearable, let name = entry.companion else { return false }
            switch look {
            case .any: break
            case .threeD: guard entry.looks.contains(.threeD) else { return false }
            case .twoD: guard entry.looks.contains(.twoD) else { return false }
            }
            switch maker {
            case .anyone: break
            case .sidefolk: guard entry.official else { return false }
            case .others: guard !entry.official else { return false }
            }
            if hideOwned, owned.contains(name) { return false }
            return entry.matches(text, extra: words(entry))
        }
        let byName: (AddonEntry, AddonEntry) -> Bool = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        switch sort {
        case .name:
            return shown.sorted(by: byName)
        case .newest:
            // Undated last; ISO dates order as text.
            return shown.sorted { a, b in a.published == b.published ? byName(a, b) : (a.published ?? "") > (b.published ?? "") }
        case .smallest:
            return shown.sorted { a, b in a.bytes == b.bytes ? byName(a, b) : a.bytes < b.bytes }
        }
    }

    /// The orders worth offering for `entries`: Newest only when the catalog dates them.
    public static func sorts(for entries: [AddonEntry]) -> [Sort] {
        entries.contains { $0.published != nil } ? Sort.allCases : [.name, .smallest]
    }

    /// The makers worth offering: a choice between Sidefolk and others only when the gallery has both.
    public static func offersMakers(_ entries: [AddonEntry]) -> Bool {
        entries.contains(where: \.official) && entries.contains { !$0.official }
    }

    /// Looks are worth filtering by only when some companions come in 2D and some don't.
    public static func offersLooks(_ entries: [AddonEntry]) -> Bool {
        Set(entries.map { $0.looks.contains(.twoD) }).count > 1
    }
}

extension AddonEntry {
    /// A companion this copy can wear: any character but the retired ones (D54, D56), whose names stay Sidefolk's.
    public var wearable: Bool {
        guard kind == .companion, let name = companion else { return false }
        return CompanionChoice(rawValue: name).map { !$0.isRetired } ?? true
    }

    /// The looks a gallery companion comes in: 3D, and 2D too for one Sidefolk has a vector rig for (D59).
    public var looks: [CompanionDimension] {
        companion.flatMap(CompanionChoice.init(rawValue:))?.dimensions ?? [.threeD]
    }
}
