import Foundation

/// One of the Mac's own apps Sidefolk reaches through Apple Events (DECISIONS D38). macOS asks the
/// person once per app ("“Sidefolk” wants access to control “Notes”"); the answer lives in System
/// Settings › Privacy & Security › Automation.
public enum MacApp: String, Sendable, CaseIterable {
    case notes, reminders

    public var bundleId: String {
        switch self {
        case .notes: "com.apple.Notes"
        case .reminders: "com.apple.reminders"
        }
    }

    /// The app's name as the Mac shows it, in the person's language ("Notizen" in German); Apple's own
    /// name, as the glossary asks. Falls back to the English name when the app isn't where macOS keeps it.
    public var displayName: String {
        let path = "/System/Applications/\(englishName).app"
        guard FileManager.default.fileExists(atPath: path) else { return englishName }
        let shown = FileManager.default.displayName(atPath: path)
        return shown.hasSuffix(".app") ? String(shown.dropLast(4)) : shown
    }

    /// The name the model reads (D28: what models read stays English).
    public var englishName: String {
        switch self {
        case .notes: "Notes"
        case .reminders: "Reminders"
        }
    }

    /// What the person sees when macOS refused: where the switch is, with a button to that page.
    public var permissionCard: ResultCard {
        let name = displayName
        return ResultCard(kind: .info, title: String(localized: "Sidefolk needs your OK to use \(name)"),
                          subtitle: String(localized: "System Settings › Privacy & Security › Automation"),
                          detail: String(localized: "Switch on \(name) under Sidefolk, then ask again."),
                          url: PrivacyPane.automation.rawValue)
    }
}

/// System Settings pages Sidefolk may open for the person when macOS needs their OK. Only these: a
/// card's link is otherwise a web address.
public enum PrivacyPane: String, Sendable, CaseIterable {
    case automation = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"

    public static func isKnown(_ url: String?) -> Bool { url.flatMap(PrivacyPane.init(rawValue:)) != nil }
}

/// Why an Apple Events call didn't work, in the terms the person can act on.
public enum AppleEventsError: Error, Sendable, Equatable {
    /// The person said no, or switched the app off, in Privacy & Security › Automation (-1743).
    case notPermitted(MacApp)
    /// macOS is still waiting for the person's answer, or the app didn't reply in time (-1712, timeout).
    case noAnswer(MacApp)
    /// The app isn't installed or couldn't start (-600, -10810 …).
    case unavailable(MacApp)
    /// The app reported something else; `code` is its Apple Events error number.
    case failed(MacApp, code: Int, message: String)

    static func from(code: Int, message: String, app: MacApp) -> AppleEventsError {
        switch code {
        case -1743, -1744: .notPermitted(app)
        case -1712: .noAnswer(app)
        case -600, -609, -10660, -10810, -10814, -10827: .unavailable(app)
        default: .failed(app, code: code, message: message)
        }
    }

    /// What the person reads. Permission problems are not thrown as this: the tools turn them into a
    /// result with a button to System Settings (`MacAppAccess.permissionResult`).
    public var userFacing: UserFacingError {
        switch self {
        case .notPermitted(let app):
            let name = app.displayName
            return UserFacingError(verbatim: String(localized: "macOS didn't let Sidefolk use \(name). Nothing was changed."),
                                   recovery: String(localized: "In System Settings › Privacy & Security › Automation, switch on \(name) under Sidefolk."),
                                   detail: "apple events: not permitted")
        case .noAnswer(let app):
            let name = app.displayName
            return UserFacingError(verbatim: String(localized: "\(name) didn't answer in time. Nothing was changed."),
                                   recovery: String(localized: "If macOS is asking whether Sidefolk may use \(name), answer it, then try again."),
                                   detail: "apple events: no answer")
        case .unavailable(let app):
            let name = app.displayName
            return UserFacingError(verbatim: String(localized: "I couldn't start \(name). Nothing was changed."),
                                   recovery: String(localized: "Open \(name) once yourself, then try again."), detail: "apple events: unavailable")
        case .failed(let app, let code, let message):
            let name = app.displayName
            return UserFacingError(verbatim: String(localized: "\(name) couldn't do that. Nothing was changed."),
                                   detail: "apple events \(code): \(message.clipped(200))")
        }
    }
}

/// Runs a fixed JavaScript for Automation program against one Mac app and returns the JSON it
/// produced. The live runner is `OsascriptRunner`; tests use a fake that answers like the app.
///
/// Programs are Sidefolk's own constants (`NotesScripts`, `RemindersScripts`). The model never writes
/// script: it fills typed tool inputs, which reach the program only as the JSON value `params`.
public protocol AppleEventsRunner: Sendable {
    /// - Parameters:
    ///   - program: the body of the script; it defines `main(app, params)` and returns plain JSON.
    ///   - name: which program (for fakes and logs), e.g. "notes.index".
    /// - Returns: what `main` returned.
    /// - Throws: `AppleEventsError`.
    func run(_ program: String, name: String, params: JSONValue, app: MacApp, timeout: TimeInterval) async throws -> JSONValue
}

/// Wraps a program so the runner gets one line of ASCII JSON back: `{"ok": …}` or `{"error": {number, message}}`.
public enum AutomationScript {
    public static func source(program: String, params: JSONValue, app: MacApp) -> String {
        source(program: program, params: params, appExpression: "Application(\(asciiJSON(.string(app.bundleId))))")
    }

    /// - Parameter appExpression: JavaScript that yields the app object `main` works on. Tests give a
    ///   stand-in object model here, so the real programs run without a single Apple Event.
    static func source(program: String, params: JSONValue, appExpression: String) -> String {
        """
        const params = \(asciiJSON(params));
        \(program)
        function run() {
          let out;
          try {
            out = { ok: main(\(appExpression), params) };
          } catch (e) {
            out = { error: { number: (e && e.errorNumber) || 0, message: String((e && e.message) || e) } };
          }
          // ASCII only, so the bytes osascript prints never depend on its text encoding.
          return JSON.stringify(out).replace(/[\\u007f-\\uffff]/g, c => '\\\\u' + ('0000' + c.charCodeAt(0).toString(16)).slice(-4));
        }
        """
    }

    /// Decodes what `source` printed: the `ok` value, or the error it carried.
    public static func result(_ text: String, app: MacApp) throws -> JSONValue {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = try? JSONValue.parse(trimmed) else {
            throw AppleEventsError.failed(app, code: 0, message: "unreadable output: \(trimmed.prefix(120))")
        }
        if let error = value["error"] {
            throw AppleEventsError.from(code: error["number"]?.intValue ?? 0, message: error["message"]?.stringValue ?? "", app: app)
        }
        return value["ok"] ?? .null
    }

    /// JSON text with every non-ASCII character escaped: a valid JavaScript expression whatever it
    /// holds (quotes, backslashes, U+2028), so input can never end the literal and become code.
    static func asciiJSON(_ value: JSONValue) -> String {
        var out = ""
        for unit in value.jsonString.utf16 {
            if unit < 0x80 {
                out.unicodeScalars.append(Unicode.Scalar(unit)!)
            } else {
                out += String(format: "\\u%04x", unit)
            }
        }
        return out
    }
}
