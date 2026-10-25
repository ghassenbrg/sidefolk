import Darwin
import Foundation

/// A skill: Markdown instructions that compose tools for a goal, loaded on demand. It lives in a folder
/// named after it, as `SKILL.md` with a small frontmatter (`name`, `description`, optional `tools`,
/// `model: smart`, and `source`, which Sidefolk writes for skills it creates).
public struct Skill: Sendable, Hashable {
    public enum Origin: String, Sendable, Hashable { case bundled, user }

    public var name: String
    public var description: String
    public var tools: [String]
    /// "smart" asks for the smart model when the skill is in use.
    public var model: String?
    /// Who wrote it: `user` (or missing: a file the user put there), `agent`, `routine:<id>`, `bundled`.
    public var source: String
    public var instructions: String
    public var origin: Origin
    public var folder: URL

    /// Bundled with Sidefolk or written by the user. Anything else is untrusted when loaded (SECURITY T3).
    public var trusted: Bool { origin == .bundled || source == "user" }
}

public struct SkillSummary: Sendable, Hashable {
    public var name: String
    public var description: String
    public var trusted: Bool
}

/// Reads skills from the user's Skills folder and the bundled `Resources/Skills`, and writes new ones.
/// A user skill with the same name as a bundled one replaces it.
public final class SkillLibrary: Sendable {
    public static let fileName = "SKILL.md"
    public static let namePattern = #"^[a-z0-9][a-z0-9-]{0,63}$"#
    static let maxFileBytes = 64 * 1024
    public static let maxInstructions = 20_000

    public let userDirectory: URL
    public let bundledDirectory: URL?
    private let events: EventBus?
    private let trash: @Sendable (URL) throws -> URL?

    /// - Parameters:
    ///   - bundledDirectory: `Resources/Skills` in the app bundle (or the repo in development).
    ///   - events: told `.dataChanged(.skills)` after a skill is created, deleted or restored.
    ///   - trash: moves a deleted skill folder to the Trash and returns where it went (tests inject one).
    public init(userDirectory: URL, bundledDirectory: URL?, events: EventBus? = nil,
                trash: @escaping @Sendable (URL) throws -> URL? = SkillLibrary.moveToTrash) {
        self.userDirectory = userDirectory
        self.bundledDirectory = bundledDirectory
        self.events = events
        self.trash = trash
    }

    public convenience init(paths: SidefolkPaths, bundledDirectory: URL?, events: EventBus? = nil) {
        self.init(userDirectory: paths.skills, bundledDirectory: bundledDirectory, events: events)
    }

    public static func moveToTrash(_ url: URL) throws -> URL? {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return result as URL?
    }

    // MARK: Reading

    /// Every readable skill, user ones replacing bundled ones of the same name, sorted by name.
    public func skills() -> [Skill] {
        var byName: [String: Skill] = [:]
        if let bundledDirectory { for s in Self.read(bundledDirectory, origin: .bundled) { byName[s.name] = s } }
        for s in Self.read(userDirectory, origin: .user) { byName[s.name] = s }
        return byName.values.sorted { $0.name < $1.name }
    }

    /// Names and one-line descriptions for the context builder.
    public func index() -> [SkillSummary] {
        skills().map { SkillSummary(name: $0.name, description: $0.description, trusted: $0.trusted) }
    }

    public func skill(named name: String) -> Skill? { skills().first { $0.name == name } }

    private static func read(_ directory: URL, origin: Skill.Origin) -> [Skill] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.sorted().compactMap { name in
            guard name.range(of: namePattern, options: .regularExpression) != nil else { return nil }
            let folder = directory.appendingPathComponent(name, isDirectory: true)
            guard let st = ExtensionFS.lstat(folder.path), ExtensionFS.isDirectory(st) else { return nil }
            do {
                return try load(folder: folder, origin: origin)
            } catch {
                Log.shared.warning("skills", "skipped \(name)", ["error": String(describing: error)])
                return nil
            }
        }
    }

    static func load(folder: URL, origin: Skill.Origin) throws -> Skill {
        let file = folder.appendingPathComponent(fileName).path
        guard let st = ExtensionFS.lstat(file), ExtensionFS.isRegular(st), Int(st.st_size) <= maxFileBytes else {
            throw UserFacingError("\(fileName) is missing, a link, or larger than 64 KiB.")
        }
        let text = try String(contentsOfFile: file, encoding: .utf8)
        let (front, body) = try SkillDocument.parse(text)
        guard let name = front["name"]?.first, name == folder.lastPathComponent else {
            throw UserFacingError("The skill's name must match its folder.")
        }
        guard let description = front["description"]?.first, !description.isEmpty else {
            throw UserFacingError("The skill needs a description.")
        }
        let model = front["model"]?.first.flatMap { ["smart", "fast"].contains($0) ? $0 : nil }
        return Skill(name: name, description: ExtensionText.line(description, characters: 500),
                     tools: (front["tools"] ?? []).map { ExtensionText.line($0, characters: 80) }, model: model,
                     source: origin == .bundled ? "bundled" : (front["source"]?.first ?? "user"),
                     instructions: body.trimmingCharacters(in: .whitespacesAndNewlines), origin: origin, folder: folder)
    }

    // MARK: Writing

    /// Writes a new skill into the user's folder. Names of existing skills (bundled included) are refused.
    @discardableResult
    public func create(name: String, description: String, instructions: String, tools: [String] = [],
                       model: String? = nil, source: String) throws -> Skill {
        try Self.check(name: name, description: description, instructions: instructions)
        guard skill(named: name) == nil else { throw UserFacingError("There's already a skill called “\(name)”.") }
        try ExtensionFS.makePrivateDirectory(userDirectory)
        let folder = userDirectory.appendingPathComponent(name, isDirectory: true)
        guard mkdir(folder.path, 0o700) == 0 else { throw UserFacingError("Couldn't create the skill “\(name)”.") }
        let text = SkillDocument.render(name: name, description: description, tools: tools, model: model, source: source,
                                        instructions: instructions)
        let file = folder.appendingPathComponent(Self.fileName).path
        let fd = open(file, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw UserFacingError("Couldn't write the skill “\(name)”.") }
        let ok = Data(text.utf8).withUnsafeBytes { raw in write(fd, raw.baseAddress, raw.count) == raw.count }
        close(fd)
        guard ok else { throw UserFacingError("Couldn't write the skill “\(name)”.") }
        events?.changed(.skills)
        return try Self.load(folder: folder, origin: .user)
    }

    static func check(name: String, description: String, instructions: String) throws {
        guard name.range(of: namePattern, options: .regularExpression) != nil else {
            throw UserFacingError("A skill name uses lowercase letters, digits and dashes, like plan-a-trip.")
        }
        let d = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !d.isEmpty, d.count <= 500 else { throw UserFacingError("A skill needs a description of at most 500 characters.") }
        let i = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !i.isEmpty, i.count <= maxInstructions else {
            throw UserFacingError("A skill needs instructions of at most \(maxInstructions) characters.")
        }
    }

    /// Moves a user skill to the Trash; bundled skills can't be deleted. Returns where it went.
    @discardableResult
    public func delete(name: String) throws -> URL? {
        guard let s = skill(named: name) else { throw ToolError.notFound("a skill called “\(name)”") }
        guard s.origin == .user else { throw UserFacingError("“\(name)” comes with Sidefolk and can't be deleted.") }
        let trashed = try trash(s.folder)
        events?.changed(.skills)
        return trashed
    }

    /// Puts a deleted skill back (undo).
    public func restore(_ trashed: URL, name: String) throws {
        let folder = userDirectory.appendingPathComponent(name, isDirectory: true)
        guard ExtensionFS.lstat(folder.path) == nil else { throw UserFacingError("A skill called “\(name)” exists again.") }
        try FileManager.default.moveItem(at: trashed, to: folder)
        events?.changed(.skills)
    }
}

/// The `SKILL.md` format: `---` frontmatter of `key: value` lines (lists as `[a, b]` or `- item`
/// lines, values optionally quoted), then the Markdown instructions. Unknown keys are ignored so
/// skills written for other tools still load.
enum SkillDocument {
    static func parse(_ text: String) throws -> ([String: [String]], String) {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            throw UserFacingError("SKILL.md must start with a --- frontmatter block.")
        }
        lines.removeFirst()
        guard let end = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            throw UserFacingError("SKILL.md's frontmatter isn't closed with ---.")
        }
        var front: [String: [String]] = [:]
        var lastKey: String?
        for raw in lines[..<end] {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("- "), let key = lastKey {
                front[key, default: []].append(unquote(String(line.dropFirst(2))))
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            lastKey = key
            if value.hasPrefix("["), value.hasSuffix("]") {
                front[key] = value.dropFirst().dropLast().split(separator: ",").map { unquote(String($0)) }.filter { !$0.isEmpty }
            } else {
                front[key] = value.isEmpty ? [] : [unquote(value)]
            }
        }
        return (front, lines[(end + 1)...].joined(separator: "\n"))
    }

    static func unquote(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard s.count >= 2, let q = s.first, q == "\"" || q == "'", s.last == q else { return s }
        let inner = String(s.dropFirst().dropLast())
        return q == "\"" ? inner.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\") : inner
    }

    static func quote(_ s: String) -> String {
        let flat = s.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        return "\"" + flat.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func render(name: String, description: String, tools: [String], model: String?, source: String,
                       instructions: String) -> String {
        var out = ["---", "name: \(name)", "description: \(quote(description.trimmingCharacters(in: .whitespacesAndNewlines)))"]
        if !tools.isEmpty { out.append("tools: [" + tools.map(quote).joined(separator: ", ") + "]") }
        if let model { out.append("model: \(model)") }
        out.append("source: \(quote(source))")
        out.append("---")
        out.append("")
        out.append(instructions.trimmingCharacters(in: .whitespacesAndNewlines))
        return out.joined(separator: "\n") + "\n"
    }
}
