import Foundation

/// Sidefolk's own extensions that do everything a smaller one does (D67). While the bigger one is on, the smaller one
/// rests: its tools and commands step aside (the AI and Ask would otherwise find two answers to "how much disk space
/// do I have"), it offers no new heads-ups, and Settings says why. Heads-ups already running keep running. Turning the
/// bigger one off or removing it brings the smaller one back by itself: nothing is switched off for the person.
/// Only between Sidefolk's own (built in or from the gallery), so no extension can quiet another.
enum ExtensionOverlap {
    /// Smaller → bigger.
    static let includedIn: [String: String] = [
        "dev.sidefolk.system-vitals": "dev.sidefolk.system-vitals-plus",
    ]
}
