#if DEBUG
import SidefolkCore

/// Made-up extensions for the debug samples (D98): the app names no real one, so the UI snapshots show what an
/// extension can do with these. Their ids sit under Sidefolk's prefix where a sample is meant to read as its own.
enum SampleAddons {
    private static func own(_ name: String) -> String { AddonEntry.officialPrefix + name }

    static let repoPal = own("repo-pal")
    static let timeZones = own("time-zones")
    static let macPulse = own("mac-pulse")
    static let macPulsePlus = own("mac-pulse-plus")
    static let skyWatch = own("sky-watch")
    static let pasteShelf = own("paste-shelf")
    static let stayUp = own("stay-up")
    static let castAlong = own("cast-along")
    static let codeMaker = own("code-maker")
    static let newsstand = own("newsstand")
}
#endif
