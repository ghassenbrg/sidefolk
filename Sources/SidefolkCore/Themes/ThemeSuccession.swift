import Foundation

/// Themes Sidefolk no longer ships and what took their place (D92). A built-in that left the app has no files any
/// more, so the person moves to its successor at once; a gallery theme that left the gallery stays installed and
/// usable (D65), and its successor is offered once.
public enum ThemeSuccession {
    public struct Retired: Sendable, Equatable {
        public var name: String
        public var successor: String
        /// A built-in whose files are gone (moved), not a gallery theme that may still be installed (offered).
        public var wasBuiltIn: Bool
    }

    public static let retired: [String: Retired] = [
        "dev.sidefolk.theme.field-notes": Retired(name: "Field Notes", successor: "dev.sidefolk.theme.paper-garden", wasBuiltIn: true),
        "dev.sidefolk.theme.night-shift": Retired(name: "Night Shift", successor: "dev.sidefolk.theme.night-studio", wasBuiltIn: true),
        "dev.sidefolk.theme.daylight": Retired(name: "Daylight", successor: ThemeTokens.harbor.id, wasBuiltIn: false),
    ]

    public enum Step: Sendable, Equatable {
        /// The theme in use left the app: wear `to` instead (the settings already say so) and tell the person once.
        case moved(from: Retired, to: String)
        /// The theme in use left the gallery but is still here: offer `successor` once.
        case offer(Retired, id: String)
    }

    /// What to do at launch for the theme in `settings`, changing them when the theme moves. `installed` says whether a
    /// theme with that id is still on this Mac (a gallery copy in the themes folder). A followed folder is the
    /// person's own theme and is left alone.
    public static func step(_ settings: inout AppSettings, installed: (String) -> Bool) -> Step? {
        guard settings.themeFolder == nil, let old = retired[settings.theme] else { return nil }
        if old.wasBuiltIn || !installed(settings.theme) {
            let from = settings.theme
            settings.theme = old.successor
            // Night Shift was compact; its people keep that spacing unless they chose one themselves.
            if from == "dev.sidefolk.theme.night-shift", settings.density == nil { settings.density = .compact }
            return .moved(from: old, to: old.successor)
        }
        guard !settings.themeSuccessorsOffered.contains(settings.theme) else { return nil }
        settings.themeSuccessorsOffered.append(settings.theme)
        return .offer(old, id: settings.theme)
    }
}
