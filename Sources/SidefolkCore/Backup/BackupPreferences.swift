import Foundation

/// The small conveniences the app keeps in its own defaults rather than its database (D91 amended): where Home and
/// Settings stood and how big, where the companion stood on each display, the person's keyboard shortcuts, where each
/// palette opens, the extension list's filter, Catch Me's best and which folks were introduced. A backup carries them
/// as `preferences.json`; a restore sets them and keeps what it replaced for Undo restore.
///
/// Only the names listed here, with plain values (text, numbers, switches, lists of those), go either way: a backup
/// can't set anything else in the app's defaults (its language, its text direction, macOS's own keys). The language
/// chosen in Settings isn't carried: it would only take effect at yet another relaunch.
public enum BackupPreferences {
    static let file = "preferences.json"
    static let before = "preferences-before.json"

    static let names: Set<String> = [
        "NSWindow Frame SidefolkHome", "NSWindow Frame SidefolkSettingsSidebar",
        "companion.catchBest", "introducedFolks", "settings.extensions.show",
    ]

    /// Whether a name in the app's defaults travels with a backup.
    static func carries(_ name: String) -> Bool {
        names.contains(name) || name.hasPrefix("companion.position.") || name.hasPrefix("KeyboardShortcuts_")
            || (name.hasPrefix("palette.") && name.hasSuffix(".position"))
    }

    /// What of the app's defaults (`UserDefaults.persistentDomain`) a backup carries.
    public static func pick(_ domain: [String: Any]) -> [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        for (name, value) in domain where carries(name) {
            if let plain = plain(value) { out[name] = plain }
        }
        return out
    }

    private static func plain(_ value: Any) -> JSONValue? {
        switch value {
        case let s as String: return .string(s)
        case let n as NSNumber:
            return CFGetTypeID(n) == CFBooleanGetTypeID() ? .bool(n.boolValue) : .number(n.doubleValue)
        case let list as [Any]:
            let items = list.compactMap(plain)
            return items.count == list.count && items.allSatisfy({ if case .array = $0 { false } else { true } }) ? .array(items) : nil
        default: return nil
        }
    }

    private static func object(_ value: JSONValue) -> Any? {
        switch value {
        case .string(let s): s
        case .bool(let b): b
        // Whole numbers go back as integers (Catch Me's best is read with `integer(forKey:)`).
        case .number(let n): n.rounded() == n && abs(n) < 1e15 ? Int(n) as Any : n
        case .array(let items): items.compactMap(object)
        case .null, .object: nil
        }
    }

    /// Sets `values` (the carried names only), and returns what each was before (nil when it wasn't set).
    static func apply(_ values: [String: JSONValue], to defaults: UserDefaults) -> [String: JSONValue?] {
        var replaced: [String: JSONValue?] = [:]
        for (name, value) in values where carries(name) {
            guard let object = object(value) else { continue }
            replaced.updateValue(defaults.object(forKey: name).flatMap(plain), forKey: name)
            defaults.set(object, forKey: name)
        }
        return replaced
    }

    /// Undo restore: each name back as it was, removed where it wasn't set.
    static func putBack(_ replaced: [String: JSONValue?], to defaults: UserDefaults) {
        for (name, value) in replaced where carries(name) {
            if let value, let object = object(value) { defaults.set(object, forKey: name) } else { defaults.removeObject(forKey: name) }
        }
    }
}
