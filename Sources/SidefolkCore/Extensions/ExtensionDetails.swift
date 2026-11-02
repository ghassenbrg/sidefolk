import Foundation

// What a manifest says about an extension beyond what it runs (D98): requests to try, the sentence for a call, the
// services it talks to, what it replaces. They used to be tables in the app, by extension id; now an extension brings
// its own, and an update changes them without a Sidefolk release.

extension ExtensionManifest {
    public static let maxExamples = 3
    public static let maxServices = 8
    public static let maxHosts = 16
    public static let maxReplaces = 8

    /// A public service the program talks to. The sandbox can't hold a program to host names (SECURITY §3), so this is
    /// its author's word: shown to everyone, and believed only for Sidefolk's own signed packs (D47, D98).
    public struct Service: Sendable, Hashable, Codable {
        /// As the approval card says it, inside a translated sentence: a brand or a site, never a phrase that needs an
        /// article ("It goes only to ecb.europa.eu"). The same in every language.
        public var name: String
        /// Every host the program's code may reach.
        public var hosts: [String]

        public init(name: String, hosts: [String]) {
            self.name = name
            self.hosts = hosts
        }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(["name", "hosts"])
            let c = try decoder.container(keyedBy: AnyKey.self)
            name = try c.decode(String.self, forKey: "name")
            hosts = try c.decode([String].self, forKey: "hosts")
        }
    }
}

/// What a tool's call is about to do, as one sentence for its approval card and Activity: "Clone {url} into
/// {destination}" rather than the title and a JSON object. Only Sidefolk's own signed packs are believed (T1): anyone
/// else's sentence could say one thing while the call does another, so theirs is never shown.
///
/// A summary is one text, or several forms tried in order, each with `if` or `unless` naming an argument:
/// `[{"unless": "from", "text": "Convert {time} here"}, {"text": "Convert {time} in {from}"}]`.
public struct ToolSummary: Sendable, Hashable, Decodable {
    public struct Form: Sendable, Hashable, Decodable {
        public var text: String
        /// This form only when that argument is there and isn't false.
        public var when: String?
        /// This form only when that argument is missing or false.
        public var unless: String?

        public init(text: String, when: String? = nil, unless: String? = nil) {
            self.text = text
            self.when = when
            self.unless = unless
        }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(["text", "if", "unless"])
            let c = try decoder.container(keyedBy: AnyKey.self)
            text = try c.decode(String.self, forKey: "text")
            when = try c.decodeIfPresent(String.self, forKey: "if")
            unless = try c.decodeIfPresent(String.self, forKey: "unless")
        }
    }

    public var forms: [Form]

    public static let maxForms = 4
    /// How long one form may be, before the arguments go in.
    public static let maxCharacters = 120

    public init(forms: [Form]) { self.forms = forms }

    public init(from decoder: Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            forms = [Form(text: text)]
        } else {
            forms = try decoder.singleValueContainer().decode([Form].self)
        }
    }

    /// The sentence for these arguments, built from them exactly (T1), or nil when an argument it needs is missing or
    /// can't be said in words: the card then shows the title and the arguments as they are, as for everyone else's tools.
    /// - Parameters:
    ///   - texts: the forms' words in the person's language, one per form; the manifest's own otherwise.
    ///   - folders: arguments naming a file or folder (`tools.<name>.paths`), shown the way Sidefolk shows paths.
    public func sentence(for input: JSONValue, texts: [String]? = nil, folders: Set<String> = []) -> String? {
        for (index, form) in forms.enumerated() where Self.holds(form, input) {
            let text = texts.flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? form.text
            return Self.fill(text, input: input, folders: folders)
        }
        return nil
    }

    private static func holds(_ form: Form, _ input: JSONValue) -> Bool {
        func given(_ name: String) -> Bool {
            guard let value = input[name], !value.isNull else { return false }
            return value.boolValue != false
        }
        if let name = form.when, !given(name) { return false }
        if let name = form.unless, given(name) { return false }
        return true
    }

    private static func fill(_ text: String, input: JSONValue, folders: Set<String>) -> String? {
        var out = text
        for name in placeholders(in: text) {
            guard let value = input[name], let shown = shown(value, folder: folders.contains(name)) else { return nil }
            out = out.replacingOccurrences(of: "{\(name)}", with: shown)
        }
        return out
    }

    /// An argument in words: never markup or a line break that could pass for part of the card (T1).
    private static func shown(_ value: JSONValue, folder: Bool) -> String? {
        switch value {
        case .string(let raw):
            let line = ToolFormat.oneLine(ExtensionText.clean(raw), 200)
            guard !line.isEmpty else { return nil }
            return folder ? FolderAccess.displayPath((line as NSString).expandingTildeInPath) : line
        case .number(let n):
            return n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
        case .array(let items):
            let all = items.compactMap(\.stringValue).map { ToolFormat.oneLine(ExtensionText.clean($0), 60) }
            return all.count != items.count || all.isEmpty || all.contains(where: \.isEmpty) ? nil : Wording.list(all)
        default:
            return nil
        }
    }

    static func placeholders(in text: String) -> [String] {
        text.matches(of: /\{([a-z_][a-z0-9_]{0,63})\}/).map { String($0.1) }
    }

    /// Why a form's text can't be a summary: plain text on one line, whose only braces are its placeholders.
    static func problem(with text: String, maxCharacters: Int) -> String? {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, text.count <= maxCharacters, ExtensionText.clean(text) == text,
              !text.contains(where: \.isNewline) else {
            return "must be one line of 1–\(maxCharacters) characters of plain text."
        }
        let left = text.replacing(/\{[a-z_][a-z0-9_]{0,63}\}/, with: "")
        return left.contains("{") || left.contains("}") ? "has braces that aren't a {parameter}." : nil
    }
}

extension ManifestValidator {
    /// Examples, summaries, services and `replaces`. All of it is the author's word, so it is held to plain text within
    /// limits here, and what it is believed for is decided where it is used.
    func checkDetails(_ m: ExtensionManifest, issues: inout [ValidationIssue], warnings: inout [String]) {
        func plain(_ text: String, max: Int) -> Bool {
            !text.trimmingCharacters(in: .whitespaces).isEmpty && text.count <= max && ExtensionText.clean(text) == text && !text.contains(where: \.isNewline)
        }
        if m.examples.count > ExtensionManifest.maxExamples {
            issues.append(ValidationIssue(field: "examples", message: "can hold at most \(ExtensionManifest.maxExamples)."))
        }
        for (index, example) in m.examples.enumerated() where !plain(example, max: 120) {
            issues.append(ValidationIssue(field: "examples[\(index)]", message: "must be one line of 1–120 characters of plain text."))
        }

        var summaries = false
        for (name, meta) in m.tools.sorted(by: { $0.key < $1.key }) {
            guard let summary = meta.summary else { continue }
            summaries = true
            let field = "tools.\(name).summary"
            if summary.forms.isEmpty || summary.forms.count > ToolSummary.maxForms {
                issues.append(ValidationIssue(field: field, message: "must have 1–\(ToolSummary.maxForms) forms."))
            }
            for (index, form) in summary.forms.enumerated() {
                let at = summary.forms.count > 1 ? "\(field)[\(index)]" : field
                if let problem = ToolSummary.problem(with: form.text, maxCharacters: ToolSummary.maxCharacters) {
                    issues.append(ValidationIssue(field: at, message: problem))
                }
                for condition in [form.when, form.unless].compactMap({ $0 })
                where condition.range(of: Self.namePattern, options: .regularExpression) == nil {
                    issues.append(ValidationIssue(field: at, message: "names “\(condition)”, which isn't a parameter's name."))
                }
            }
        }
        if summaries, !AddonEntry.isOfficial(id: m.id) {
            warnings.append("Summaries are shown only for packs Sidefolk signs: approval cards show everyone else's tools with their title and exact arguments.")
        }

        if !m.services.isEmpty, !m.permissions.network {
            issues.append(ValidationIssue(field: "services", message: "needs permissions.network: true."))
        }
        if m.services.count > ExtensionManifest.maxServices {
            issues.append(ValidationIssue(field: "services", message: "can hold at most \(ExtensionManifest.maxServices)."))
        }
        for (index, service) in m.services.enumerated() {
            let field = "services[\(index)]"
            if !plain(service.name, max: 40) {
                issues.append(ValidationIssue(field: "\(field).name", message: "must be one line of 1–40 characters of plain text."))
            }
            if service.hosts.isEmpty || service.hosts.count > ExtensionManifest.maxHosts {
                issues.append(ValidationIssue(field: "\(field).hosts", message: "must list 1–\(ExtensionManifest.maxHosts) hosts."))
            }
            for host in service.hosts where host.range(of: #"^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$"#, options: .regularExpression) == nil {
                issues.append(ValidationIssue(field: "\(field).hosts", message: "“\(host.prefix(60))” isn't a host name in lower case, like api.example.com."))
            }
        }

        if m.replaces.count > ExtensionManifest.maxReplaces {
            issues.append(ValidationIssue(field: "replaces", message: "can hold at most \(ExtensionManifest.maxReplaces)."))
        }
        for id in m.replaces where id == m.id || id.range(of: Self.idPattern, options: .regularExpression) == nil {
            issues.append(ValidationIssue(field: "replaces", message: "“\(id.prefix(60))” isn't another extension's id."))
        }
    }
}
