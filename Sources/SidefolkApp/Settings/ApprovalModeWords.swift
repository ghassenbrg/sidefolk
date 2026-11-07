import Foundation
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
            String(localized: "Gets on with it. Asks before deleting things you can't get back, before sending anything out after reading outside content, and for folders you haven't shared.", comment: "Settings › Trust: Auto's line")
        case .fullAccess:
            String(localized: "Does what you ask without asking, even after reading a web page or file. Only your off switches and protected places hold. Other apps still ask each time, unless you let them in the sheet.", comment: "Settings › Trust: Full access's line")
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

    /// The Trust page's headline while this mode is on.
    var headline: String {
        switch self {
        case .askEveryTime: String(localized: "Guard asks before every step", comment: "Settings › Trust: the headline in Ask every time")
        case .askOncePerKind: String(localized: "Guard asks once for each kind of thing", comment: "Settings › Trust: the headline in Ask once per kind")
        case .auto: String(localized: "Sidefolk acts on its own, and asks before risky steps", comment: "Settings › Trust: the headline in Auto")
        case .fullAccess: String(localized: "Full access is on", comment: "Settings › Trust: the headline in Full access")
        }
    }

    /// What the mode does to one real kind of step, for its card in Trust.
    var example: AttributedString {
        let text = switch self {
        case .askEveryTime: String(localized: "Move 12 PDFs to Invoices: **asks**. The same tomorrow: **asks again**.",
                                   comment: "Settings › Trust: an example of Ask every time; keep the ** marks around the bold words")
        case .askOncePerKind: String(localized: "Move 12 PDFs: **asks once**. Choose Always allow, and moving files goes ahead from then on.",
                                     comment: "Settings › Trust: an example of Ask once per kind; keep the ** marks")
        case .auto: String(localized: "Reads a page, then renames 3 files **on its own**. **Asks** before deleting for good or sending anything out.",
                           comment: "Settings › Trust: an example of Auto; keep the ** marks")
        case .fullAccess: String(localized: "Runs `npm test` **without asking**, even after reading a web page. Nothing asks.",
                                 comment: "Settings › Trust: an example of Full access; keep the ** marks and the command as it is")
        }
        return (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    var exampleSymbol: String {
        switch self {
        case .askEveryTime, .askOncePerKind: "folder"
        case .auto: "globe"
        case .fullAccess: "terminal"
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
