import Foundation

// Opening links and apps. Links go to the user's default handler; Sidefolk never fetches them here.

struct OpenURLTool: Tool {
    let platform: any PlatformBridge

    let spec = ToolSpec(
        name: "open.url", title: "Open a link",
        description: """
            Open a web link (http or https) in the user's default browser. Other kinds of link, such as file:, \
            javascript: or custom app schemes, are refused. To start an email use open.email.
            """,
        inputSchema: Schema.object(["url": Schema.string("The full web address, e.g. https://example.com/pricing")], required: ["url"]),
        risk: .low, capabilities: [.apps], category: .system, mutates: false)

    func summary(for input: JSONValue) -> String { "Open \((input.string("url") ?? "").clipped(120)) in your browser" }

    func scope(for input: JSONValue) -> ToolScope { ToolScope(url: input.string("url")) }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let text = try input.requiredText("url", limit: URLPolicy.maxLength)
        let url: URL
        do { url = try URLPolicy.parseWebURL(text) } catch let v as URLPolicy.Violation { throw v.userFacing }
        guard await platform.open(url: url) else {
            throw UserFacingError("I couldn't open that link.", recovery: "Check that a browser is set up on this Mac.")
        }
        let host = url.host ?? url.absoluteString
        return ToolResult(
            text: "Opened \(url.absoluteString) in the browser.",
            card: ResultCard(kind: .web, title: "Opened \(host)", subtitle: url.absoluteString.clipped(80), url: url.absoluteString))
    }
}

/// Starts a draft in the user's mail app. It never sends anything; mailto is medium risk because the
/// subject and body travel into another app (docs/SECURITY.md T11).
struct OpenEmailTool: Tool {
    let platform: any PlatformBridge

    let spec = ToolSpec(
        name: "open.email", title: "Start an email",
        description: "Open a new, unsent email draft in the user's mail app. Sidefolk can't send it; the user reviews and sends.",
        inputSchema: Schema.object([
            "to": Schema.string("Recipient address, or several separated by commas"),
            "subject": Schema.string("Subject line"),
            "body": Schema.string("Message text"),
        ], required: ["to"]),
        risk: .medium, capabilities: [.apps], category: .system, mutates: false)

    func summary(for input: JSONValue) -> String {
        var s = "Start an email to \((input.string("to") ?? "").clipped(80))"
        if let subject = input.string("subject") { s += " about “\(subject.clipped(60))”" }
        return s
    }

    func scope(for input: JSONValue) -> ToolScope { ToolScope(url: try? Self.mailtoURL(input).absoluteString) }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let url = try Self.mailtoURL(input)
        guard await platform.open(url: url) else {
            throw UserFacingError("I couldn't start the email.", recovery: "Check that a mail app is set up on this Mac.")
        }
        let to = input.string("to") ?? ""
        return ToolResult(
            text: "Opened a new email draft to \(to.clipped(120)). Nothing was sent; the user has to review and send it.",
            card: ResultCard(kind: .info, title: "Started an email", subtitle: to.clipped(80)))
    }

    /// Builds the mailto URL ourselves so only addresses, a subject and a body can ever reach the mail app.
    static func mailtoURL(_ input: JSONValue) throws -> URL {
        let recipients = input.textList("to") ?? []
        guard !recipients.isEmpty else { throw ToolError.invalidInput("“to” needs at least one email address.") }
        guard recipients.count <= 10 else { throw UserFacingError("That's too many recipients (the limit is 10).") }
        for address in recipients where !isEmailAddress(address) {
            throw UserFacingError("“\(address.clipped(60))” doesn't look like an email address.")
        }
        var text = "mailto:" + recipients.map(encode).joined(separator: ",")
        var query: [String] = []
        if let subject = try input.optionalText("subject", limit: 200) {
            query.append("subject=" + encode(ToolFormat.oneLine(subject, 200)))
        }
        if let body = try input.optionalText("body", limit: 4_000) {
            query.append("body=" + encode(body.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")))
        }
        if !query.isEmpty { text += "?" + query.joined(separator: "&") }
        guard let url = URL(string: text) else { throw UserFacingError("I couldn't build that email link.") }
        return url
    }

    static func isEmailAddress(_ s: String) -> Bool {
        guard s.count <= 254, !s.contains(where: \.isWhitespace) else { return false }
        let parts = s.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."), !parts[1].hasPrefix("."), !parts[1].hasSuffix(".") else { return false }
        let forbidden = CharacterSet(charactersIn: "<>()[]\\;:\",")
        return s.unicodeScalars.allSatisfy { !forbidden.contains($0) && $0.properties.generalCategory != .control }
    }

    private static let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
    private static func encode(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
}

struct OpenAppTool: Tool {
    let platform: any PlatformBridge

    let spec = ToolSpec(
        name: "open.app", title: "Open an app",
        description: "Open or bring forward an app by its name (\"Safari\") or bundle identifier (\"com.apple.Safari\").",
        inputSchema: Schema.object(["name": Schema.string("App name or bundle identifier")], required: ["name"]),
        risk: .low, capabilities: [.apps], category: .system, mutates: false)

    func summary(for input: JSONValue) -> String { "Open \((input.string("name") ?? "an app").clipped(60))" }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let name = try input.requiredText("name", limit: 100)
        // A name, not a path: opening arbitrary program paths is not what this tool is for.
        guard !name.contains("/"), !name.contains("\0"), !name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            throw UserFacingError("Give me the name of an app (like “Safari”), not a file path.")
        }
        guard await platform.openApplication(name) else {
            throw UserFacingError("I couldn't open an app called “\(name.clipped(60))”.", recovery: "Check the spelling.")
        }
        return ToolResult(text: "Opened \(name).", card: ResultCard(kind: .info, title: "Opened \(name)"))
    }
}
