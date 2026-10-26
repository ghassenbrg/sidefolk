import AppKit
import SidefolkCore

/// The language Sidefolk speaks: the Mac's by default, or one chosen in Settings. macOS reads the
/// choice (`AppleLanguages` in Sidefolk's own defaults) once at launch, so a change takes a relaunch.
enum AppLanguage {
    /// The translations Sidefolk ships (Info.plist `CFBundleLocalizations`), each named in itself.
    static let supported: [(code: String, name: String)] = [
        ("en", "English"), ("fr", "Français"), ("es", "Español"), ("de", "Deutsch"), ("it", "Italiano"),
        ("pt-BR", "Português (Brasil)"), ("ja", "日本語"), ("ko", "한국어"), ("zh-Hans", "简体中文"), ("ar", "العربية"),
    ]

    private static let key = "AppleLanguages"

    /// The language chosen in Settings, or nil to follow the Mac.
    static var chosen: String? {
        get {
            let own = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?[key] as? [String]
            return own?.first
        }
        set {
            if let newValue { UserDefaults.standard.set([newValue], forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }

    /// The language this launch is speaking: the bundle's best match among its translations.
    static var current: String { Bundle.main.preferredLocalizations.first ?? "en" }

    /// AppKit lays an app out right to left only when the Mac itself reads that way; Sidefolk can
    /// speak Arabic on an English Mac, so it sets its own direction, in its own defaults (AppKit reads
    /// them through CFPreferences, which doesn't see registered defaults). Call it before
    /// `NSApplication.shared`. Text keeps its natural direction; only the layout mirrors.
    static func applyLayoutDirection() {
        let key = "AppleTextDirection"
        if Locale.Language(identifier: current).characterDirection == .rightToLeft {
            UserDefaults.standard.set(true, forKey: key)
        } else if UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName)?[key] != nil {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// What "follow the Mac" would pick, for the menu's first item.
    static var system: String {
        Bundle.preferredLocalizations(from: supported.map(\.code), forPreferences: Locale.preferredLanguages).first ?? "en"
    }

    static func name(of code: String) -> String { supported.first { $0.code == code }?.name ?? code }

    /// Quits, and opens Sidefolk again as soon as this copy is gone.
    static func relaunch() {
        do {
            let own = ProcessInfo.processInfo.environment.filter { $0.key.hasPrefix("SIDEFOLK_") }
            try Relaunch.after(pid: ProcessInfo.processInfo.processIdentifier, open: Bundle.main.bundleURL.path, environment: own)
        } catch {
            Log.shared.error("app", "could not schedule the relaunch", ["error": String(describing: error)])
            return
        }
        AppDelegate.quit()
    }
}
