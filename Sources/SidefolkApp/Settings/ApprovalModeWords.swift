import SidefolkCore

/// How each approval mode is named and explained wherever it shows (D37): Settings, the chip in the
/// Ask panel, the menu bar.
extension GuardMode {
    var title: String {
        switch self {
        case .askEveryTime: String(localized: "Ask every time")
        case .askOncePerKind: String(localized: "Ask once per kind")
        case .auto: String(localized: "Auto")
        case .fullAccess: String(localized: "Full access")
        }
    }

    /// One line: what the mode does, and what it still asks about.
    var explanation: String {
        switch self {
        case .askEveryTime:
            String(localized: "Asks before anything that changes something outside Sidefolk, even if you allowed it before.")
        case .askOncePerKind:
            String(localized: "Asks once for each kind of action and remembers “Always allow”. The default.")
        case .auto:
            String(localized: "Acts on its own. Still asks before high-risk actions and anything a web page, file or extension could have steered.")
        case .fullAccess:
            String(localized: "Acts without asking. Still asks before anything a web page, file or extension steered could send your data out.")
        }
    }

    /// The few words the Ask panel's chip has room for.
    var chipTitle: String {
        switch self {
        case .askEveryTime: String(localized: "Asks every time", comment: "A small label in the Ask panel: the approval mode")
        case .askOncePerKind: String(localized: "Asks once", comment: "A small label in the Ask panel: the approval mode")
        case .auto: String(localized: "Auto")
        case .fullAccess: String(localized: "Full access")
        }
    }

    var symbol: String {
        switch self {
        case .askEveryTime: "hand.raised"
        case .askOncePerKind: "checkmark.shield"
        case .auto: "bolt"
        case .fullAccess: "bolt.fill"
        }
    }
}
