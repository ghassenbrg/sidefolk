import Foundation

/// An accessibility attribute as words. Some views answer an attributed string where a `String` is declared; read as a
/// `String`, that crashes (`_fastCStringContents`), so the debug tree dump takes whatever object came back through here.
public enum AccessibilityText {
    public static func plain(_ value: Any?) -> String? {
        switch value {
        case nil: nil
        case let attributed as NSAttributedString: attributed.string
        case let string as String: string
        case let value?: "\(value)"
        }
    }
}
