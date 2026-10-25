import Darwin
import Foundation

/// How an extension starts, resolved at install: the pinned interpreter (nil for a compiled program)
/// and a program path relative to the extension folder, so it stays valid after the folder is copied.
public struct ExtensionLaunch: Codable, Sendable, Hashable {
    public var interpreter: ResolvedInterpreter?
    public var program: String
    public var arguments: [String]

    public init(interpreter: ResolvedInterpreter?, program: String, arguments: [String]) {
        self.interpreter = interpreter
        self.program = program
        self.arguments = arguments
    }
}

/// Everything `ManifestValidator` found: the decoded manifest, problems, and the resolved launch and
/// permissions an install would pin. `sidefolk ext validate <dir>` prints `text`.
public struct ValidationReport: Sendable {
    public var folder: URL
    public var manifest: ExtensionManifest?
    public var errors: [ValidationIssue] = []
    public var warnings: [String] = []
    public var launch: ExtensionLaunch?
    public var permissions: ExtensionPermissions?
    public var summary: PermissionSummary?

    public var isValid: Bool { errors.isEmpty && manifest != nil && launch != nil && permissions != nil }

    /// Effective risk of each declared tool after Sidefolk's floors.
    public var toolRisks: [(name: String, risk: Risk)] {
        guard let manifest, let permissions else { return [] }
        return manifest.tools.keys.sorted().map { name in
            (name, ExtensionRisk.effective(declared: manifest.tools[name]?.risk, permissions: permissions, kind: .sidefolk))
        }
    }

    /// A readable report for the command line.
    public var text: String {
        var out: [String] = []
        if let m = manifest {
            out.append("\(m.name) \(m.version) (\(m.id))")
        } else {
            out.append(folder.path)
        }
        if let launch {
            let runner = launch.interpreter.map { "\($0.name) (\($0.path)) " } ?? ""
            out.append("Runs: \(runner)\(([launch.program] + launch.arguments).joined(separator: " "))")
        }
        if let summary {
            out.append("Permissions:")
            out += summary.texts.map { "  - \($0)" }
        }
        let risks = toolRisks
        if !risks.isEmpty { out.append("Tools: " + risks.map { "\($0.name) (\($0.risk.rawValue))" }.joined(separator: ", ")) }
        if let m = manifest, !m.watchers.isEmpty { out.append("Watchers: " + m.watchers.keys.sorted().joined(separator: ", ")) }
        let cautions = warnings + (summary?.warnings ?? [])
        if !cautions.isEmpty {
            out.append("Warnings:")
            out += cautions.map { "  - \($0)" }
        }
        if errors.isEmpty {
            out.append(isValid ? "Valid." : "Not valid.")
        } else {
            out.append("Errors:")
            out += errors.map { "  - \($0)" }
            out.append("Not valid: fix the errors above.")
        }
        return out.joined(separator: "\n")
    }
}

/// Risk of an extension tool: what the manifest declares (medium if nothing), never below the floor.
/// Network, write access or an exec entry that can run anything puts every tool at medium or above;
/// plain MCP servers are unsandboxed, so they never go below medium (SECURITY T1, T13, T16).
public enum ExtensionRisk {
    public static func effective(declared: Risk?, permissions: ExtensionPermissions?, kind: ExtensionRecord.Kind) -> Risk {
        let raised = kind == .mcp || (permissions?.raisesRiskFloor ?? true)
        return max(declared ?? .medium, raised ? .medium : .low)
    }
}

/// Validates a manifest against its folder (SECURITY T13). Pure checks plus `stat`/`realpath`; it never
/// runs the extension.
public struct ManifestValidator: Sendable {
    public enum Mode: Sendable {
        /// A folder someone is about to install: its name may differ from the id (warning only).
        case source
        /// A copy under `Extensions/<id>/`: the name must equal the id.
        case installed
    }

    public static let idPattern = #"^[a-z0-9]+(\.[a-z0-9-]+)+$"#
    public static let namePattern = #"^[a-z0-9_]{1,64}$"#

    public var paths: SidefolkPaths
    public var resolver: InterpreterResolver

    public init(paths: SidefolkPaths, resolver: InterpreterResolver = .system) {
        self.paths = paths
        self.resolver = resolver
    }

    public func validate(folder: URL, mode: Mode = .source) -> ValidationReport {
        var report = ValidationReport(folder: folder)
        guard let dir = ExtensionFS.realpath(folder.path), let st = ExtensionFS.lstat(dir), ExtensionFS.isDirectory(st) else {
            report.errors.append(ValidationIssue(field: folder.path, message: "isn't a folder."))
            return report
        }
        let file = dir + "/" + ExtensionManifest.fileName
        guard let fst = ExtensionFS.lstat(file), ExtensionFS.isRegular(fst) else {
            report.errors.append(ValidationIssue(field: ExtensionManifest.fileName, message: "is missing (or is a link)."))
            return report
        }
        guard Int(fst.st_size) <= ExtensionManifest.maxBytes else {
            report.errors.append(ValidationIssue(field: ExtensionManifest.fileName, message: "is larger than 64 KiB."))
            return report
        }
        let manifest: ExtensionManifest
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: file))
            manifest = try ExtensionManifest.decode(data)
        } catch let issue as ValidationIssue {
            report.errors.append(issue)
            return report
        } catch {
            report.errors.append(ValidationIssue(field: ExtensionManifest.fileName, message: "couldn't be read."))
            return report
        }
        report.manifest = manifest
        var issues: [ValidationIssue] = []
        checkIdentity(manifest, folder: dir, mode: mode, issues: &issues, warnings: &report.warnings)
        report.launch = checkRun(manifest.run, folder: dir, issues: &issues)
        let permissions = checkPermissions(manifest.permissions, folder: dir, issues: &issues, warnings: &report.warnings)
        report.permissions = permissions
        checkTools(manifest, issues: &issues)
        checkWatchers(manifest, issues: &issues)
        report.summary = PermissionSummary.forExtension(permissions)
        report.errors = issues
        return report
    }

    // MARK: Identity

    private func checkIdentity(_ m: ExtensionManifest, folder: String, mode: Mode, issues: inout [ValidationIssue], warnings: inout [String]) {
        if m.id.count > 64 || m.id.range(of: Self.idPattern, options: .regularExpression) == nil {
            issues.append(ValidationIssue(field: "id", message: "must look like com.example.my-extension (lowercase, at least one dot, at most 64 characters)."))
        }
        let folderName = (folder as NSString).lastPathComponent
        if folderName != m.id {
            switch mode {
            case .installed:
                issues.append(ValidationIssue(field: "id", message: "“\(m.id)” doesn't match its folder “\(folderName)”."))
            case .source where folderName != m.shortName:
                warnings.append("The folder is called “\(folderName)” but the id is “\(m.id)”. Did you copy a template and forget to change the id?")
            case .source:
                break
            }
        }
        let name = m.name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty || name.count > 60 || ExtensionText.clean(name) != name {
            issues.append(ValidationIssue(field: "name", message: "must be 1–60 characters of plain text."))
        }
        if m.version.range(of: #"^\d+\.\d+(\.\d+)?([-+][0-9A-Za-z.-]+)?$"#, options: .regularExpression) == nil {
            issues.append(ValidationIssue(field: "version", message: "must look like 1.0.0."))
        }
        if let d = m.description, d.count > 300 || ExtensionText.clean(d) != d {
            issues.append(ValidationIssue(field: "description", message: "must be at most 300 characters of plain text."))
        }
        if let a = m.author, a.count > 100 || ExtensionText.clean(a) != a {
            issues.append(ValidationIssue(field: "author", message: "must be at most 100 characters of plain text."))
        }
        if let f = m.folk, f.range(of: #"^[a-z0-9-]{1,32}$"#, options: .regularExpression) == nil {
            issues.append(ValidationIssue(field: "folk", message: "must be a folk name like byte."))
        }
        if let req = m.sidefolk {
            switch Self.satisfies(req, current: SidefolkVersion.current) {
            case nil: issues.append(ValidationIssue(field: "sidefolk", message: "must look like >=1.0."))
            case false?: issues.append(ValidationIssue(field: "sidefolk", message: "needs Sidefolk \(req.dropFirst(2)) or later; this is \(SidefolkVersion.current)."))
            case true?: break
            }
        }
    }

    /// `>=X[.Y[.Z]]` against a dotted version. Nil when the requirement can't be read.
    static func satisfies(_ requirement: String, current: String) -> Bool? {
        let r = requirement.trimmingCharacters(in: .whitespaces)
        guard r.hasPrefix(">=") else { return nil }
        func parts(_ s: Substring) -> [Int]? {
            let p = s.split(separator: ".").map { Int($0) }
            guard (1...3).contains(p.count), p.allSatisfy({ $0 != nil }) else { return nil }
            return p.map { $0! } + Array(repeating: 0, count: 3 - p.count)
        }
        guard let need = parts(r.dropFirst(2).drop { $0 == " " }), let have = parts(Substring(current)) else { return nil }
        return have.lexicographicallyPrecedes(need) == false
    }

    // MARK: Run

    private func checkRun(_ run: ExtensionManifest.Run, folder: String, issues: inout [ValidationIssue]) -> ExtensionLaunch? {
        let before = issues.count
        if run.args.count > 32 || run.args.contains(where: { $0.utf8.count > 1024 || $0.contains("\0") }) {
            issues.append(ValidationIssue(field: "run.args", message: "must be at most 32 arguments of at most 1 KiB each."))
        }
        let command = run.command
        if InterpreterResolver.supported.contains(command) {
            guard let interpreter = resolver.resolve(command) else {
                let hint = command == "python3" ? " Install Apple's command line tools with xcode-select --install." : ""
                issues.append(ValidationIssue(field: "run.command", message: "\(command) isn't installed on this Mac.\(hint)"))
                return nil
            }
            guard let script = run.args.first, !script.hasPrefix("-") else {
                issues.append(ValidationIssue(field: "run.args[0]", message: "must be the script to run, inside the extension folder."))
                return nil
            }
            guard let program = insidePath(script, folder: folder, field: "run.args[0]", executable: false, issues: &issues),
                  issues.count == before else { return nil }
            return ExtensionLaunch(interpreter: interpreter, program: program, arguments: Array(run.args.dropFirst()))
        }
        if command.contains("/"), !command.hasPrefix("/"), !command.hasPrefix("~") {
            guard let program = insidePath(command, folder: folder, field: "run.command", executable: true, issues: &issues),
                  issues.count == before else { return nil }
            return ExtensionLaunch(interpreter: nil, program: program, arguments: run.args)
        }
        issues.append(ValidationIssue(field: "run.command",
                                      message: "“\(command)” isn't supported. Use python3, node, sh, or a program inside the extension folder like bin/server."))
        return nil
    }

    /// A relative path that must resolve, without links, to a regular file inside the folder.
    private func insidePath(_ rel: String, folder: String, field: String, executable: Bool, issues: inout [ValidationIssue]) -> String? {
        guard !rel.hasPrefix("/"), !rel.hasPrefix("~"), !ExtensionText.hasControlOrQuote(rel), !rel.isEmpty else {
            issues.append(ValidationIssue(field: field, message: "must be a relative path inside the extension folder."))
            return nil
        }
        guard !rel.split(separator: "/").contains("..") else {
            issues.append(ValidationIssue(field: field, message: "can't use “..”."))
            return nil
        }
        let joined = folder + "/" + rel
        guard let lst = ExtensionFS.lstat(joined), let real = ExtensionFS.realpath(joined) else {
            issues.append(ValidationIssue(field: field, message: "“\(rel)” doesn't exist in the extension folder."))
            return nil
        }
        guard ExtensionFS.isInside(real, folder), real != folder else {
            issues.append(ValidationIssue(field: field, message: "“\(rel)” points outside the extension folder."))
            return nil
        }
        guard (lst.st_mode & S_IFMT) != S_IFLNK else {
            issues.append(ValidationIssue(field: field, message: "“\(rel)” is a link; extensions can't contain links."))
            return nil
        }
        guard ExtensionFS.isRegular(lst) else {
            issues.append(ValidationIssue(field: field, message: "“\(rel)” isn't a file."))
            return nil
        }
        if executable {
            guard lst.st_mode & 0o100 != 0 else {
                issues.append(ValidationIssue(field: field, message: "“\(rel)” isn't executable (chmod +x)."))
                return nil
            }
            guard Self.isMachO(real) else {
                issues.append(ValidationIssue(field: field, message: "“\(rel)” must be a compiled program. For scripts, set run.command to python3, node or sh and put the script in run.args."))
                return nil
            }
        }
        return String(real.dropFirst(folder.count + 1))
    }

    static func isMachO(_ path: String) -> Bool {
        guard let h = FileHandle(forReadingAtPath: path), let d = try? h.read(upToCount: 4), d.count == 4 else { return false }
        try? h.close()
        let magic = d.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        return [0xFEEDFACE, 0xFEEDFACF, 0xCEFAEDFE, 0xCFFAEDFE, 0xCAFEBABE, 0xBEBAFECA].contains(magic)
    }

    // MARK: Permissions

    func checkPermissions(_ p: ExtensionManifest.Permissions, folder: String, issues: inout [ValidationIssue],
                          warnings: inout [String]) -> ExtensionPermissions {
        var result = ExtensionPermissions(network: p.network)
        for (field, list) in [("read", p.files.read), ("write", p.files.write), ("exec", p.exec)] where list.count > 32 {
            issues.append(ValidationIssue(field: "permissions.\(field)", message: "can list at most 32 entries."))
        }
        for (i, raw) in p.files.write.enumerated() {
            if let canon = checkFolder(raw, field: "permissions.files.write[\(i)]", folder: folder, issues: &issues),
               !result.write.contains(canon) {
                result.write.append(canon)
            }
        }
        for (i, raw) in p.files.read.enumerated() {
            if let canon = checkFolder(raw, field: "permissions.files.read[\(i)]", folder: folder, issues: &issues),
               !result.read.contains(canon), !result.write.contains(canon) {
                result.read.append(canon)
            }
        }
        let writable = result.write + [paths.home.path, paths.extensionData.path, paths.extensions.path, folder]
            .compactMap(FolderAccess.canonical)
        for (i, raw) in p.exec.enumerated() {
            let field = "permissions.exec[\(i)]"
            guard raw.hasPrefix("/"), !ExtensionText.hasControlOrQuote(raw) else {
                issues.append(ValidationIssue(field: field, message: "must be an absolute path like /usr/bin/pmset."))
                continue
            }
            guard let real = ExtensionFS.realpath(raw), let st = ExtensionFS.lstat(real) else {
                issues.append(ValidationIssue(field: field, message: "“\(raw)” doesn't exist."))
                continue
            }
            guard real == raw else {
                issues.append(ValidationIssue(field: field, message: "“\(raw)” is a link to \(real); list \(real) instead."))
                continue
            }
            guard ExtensionFS.isRegular(st), st.st_mode & 0o111 != 0 else {
                issues.append(ValidationIssue(field: field, message: "“\(raw)” isn't a program."))
                continue
            }
            guard st.st_uid == 0 || st.st_uid == getuid(), st.st_mode & 0o022 == 0 else {
                issues.append(ValidationIssue(field: field, message: "“\(raw)” can be changed by other users of this Mac."))
                continue
            }
            if writable.contains(where: { ExtensionFS.isInside(real, $0) }) {
                issues.append(ValidationIssue(field: field, message: "“\(raw)” is in a folder the extension or Sidefolk can write to."))
                continue
            }
            if ExtensionPermissions.canRunAnything(real) {
                warnings.append("\(field): \(real) can run anything, so the exec list no longer limits what the extension runs.")
            }
            if !result.exec.contains(real) { result.exec.append(real) }
        }
        return result
    }

    /// A folder from `files.read`/`files.write`: absolute or `~/`, canonical, and outside the T10 deny-list.
    private func checkFolder(_ raw: String, field: String, folder: String, issues: inout [ValidationIssue]) -> String? {
        guard !raw.isEmpty, !ExtensionText.hasControlOrQuote(raw) else {
            issues.append(ValidationIssue(field: field, message: "can't contain quotes, backslashes or control characters."))
            return nil
        }
        guard raw.hasPrefix("/") || raw.hasPrefix("~/") else {
            issues.append(ValidationIssue(field: field, message: "“\(raw)” must be absolute or start with ~/."))
            return nil
        }
        guard let canon = FolderAccess.canonical(raw) else {
            issues.append(ValidationIssue(field: field, message: "“\(raw)” isn't usable (“.”, “..” or a broken link)."))
            return nil
        }
        let own = [paths.home.path, paths.extensions.path, paths.extensionData.path].compactMap(FolderAccess.canonical)
        if own.contains(where: { ExtensionFS.isInside(canon, $0) || ExtensionFS.isInside($0, canon) }) || ExtensionFS.isInside(canon, folder) {
            issues.append(ValidationIssue(field: field, message: "“\(raw)” overlaps Sidefolk's own data or the extension's folder."))
            return nil
        }
        if let why = FolderAccess.forbiddenReason([canon]) {
            issues.append(ValidationIssue(field: field, message: "“\(raw)”: \(why)"))
            return nil
        }
        guard FolderAccess.isGrantable(canon) else {
            issues.append(ValidationIssue(field: field, message: "“\(raw)” is too broad; name a specific folder."))
            return nil
        }
        return canon
    }

    // MARK: Tools and watchers

    private func checkTools(_ m: ExtensionManifest, issues: inout [ValidationIssue]) {
        if m.tools.count > 128 { issues.append(ValidationIssue(field: "tools", message: "can declare at most 128 tools.")) }
        for name in m.tools.keys.sorted() {
            let field = "tools.\(name)"
            if name.range(of: Self.namePattern, options: .regularExpression) == nil {
                issues.append(ValidationIssue(field: field, message: "isn't a valid tool name (lowercase letters, digits and _)."))
            } else if ExtensionTool.registryName(short: m.shortName, tool: name).count > 64 {
                issues.append(ValidationIssue(field: field, message: "makes the full tool name ext.\(m.shortName).\(name) longer than 64 characters."))
            }
            if let t = m.tools[name]?.title, t.isEmpty || t.count > 80 || ExtensionText.clean(t) != t {
                issues.append(ValidationIssue(field: "\(field).title", message: "must be 1–80 characters of plain text."))
            }
        }
    }

    private func checkWatchers(_ m: ExtensionManifest, issues: inout [ValidationIssue]) {
        if m.watchers.count > 32 { issues.append(ValidationIssue(field: "watchers", message: "can declare at most 32 watchers.")) }
        for name in m.watchers.keys.sorted() {
            let field = "watchers.\(name)"
            guard let w = m.watchers[name] else { continue }
            if name.range(of: Self.namePattern, options: .regularExpression) == nil {
                issues.append(ValidationIssue(field: field, message: "isn't a valid watcher name (lowercase letters, digits and _)."))
            }
            if w.title.isEmpty || w.title.count > 60 || ExtensionText.clean(w.title) != w.title {
                issues.append(ValidationIssue(field: "\(field).title", message: "must be 1–60 characters of plain text."))
            }
            if let d = w.description, d.count > 300 || ExtensionText.clean(d) != d {
                issues.append(ValidationIssue(field: "\(field).description", message: "must be at most 300 characters of plain text."))
            }
            if w.config.count > 32 { issues.append(ValidationIssue(field: "\(field).config", message: "can have at most 32 settings.")) }
            for key in w.config.keys.sorted() {
                guard let f = w.config[key] else { continue }
                let kf = "\(field).config.\(key)"
                if key.range(of: Self.namePattern, options: .regularExpression) == nil {
                    issues.append(ValidationIssue(field: kf, message: "isn't a valid setting name (lowercase letters, digits and _)."))
                }
                if let d = f.default, WatcherConfig.check(d, against: f) != nil {
                    issues.append(ValidationIssue(field: "\(kf).default", message: "doesn't match its type \(f.type.rawValue)."))
                }
                if let lo = f.minimum, let hi = f.maximum, lo > hi {
                    issues.append(ValidationIssue(field: kf, message: "has a minimum above its maximum."))
                }
            }
        }
    }
}

/// Checks a watcher's settings against the fields its manifest declares.
public enum WatcherConfig {
    /// Fills defaults, rejects unknown keys and wrong types. Throws a message naming the setting.
    public static func validate(_ config: JSONValue, fields: [String: ExtensionManifest.ConfigField]) throws -> JSONValue {
        guard let object = config.isNull ? [:] : config.objectValue else {
            throw UserFacingError("The watcher's settings must be an object.")
        }
        var out: [String: JSONValue] = [:]
        for key in object.keys.sorted() where fields[key] == nil {
            throw UserFacingError("The watcher doesn't have a setting called “\(key)”.")
        }
        for (key, field) in fields {
            guard let value = object[key], !value.isNull else {
                if let d = field.default { out[key] = d } else if field.required == true {
                    throw UserFacingError("The watcher needs “\(key)”.")
                }
                continue
            }
            if let problem = check(value, against: field) { throw UserFacingError("“\(key)” \(problem)") }
            out[key] = value
        }
        return .object(out)
    }

    /// Nil when the value fits the field, otherwise what is wrong.
    static func check(_ value: JSONValue, against field: ExtensionManifest.ConfigField) -> String? {
        switch (field.type, value) {
        case (.boolean, .bool), (.string, .string): break
        case (.integer, .number(let n)) where n.rounded() == n: break
        case (.number, .number): break
        default: return "should be \(field.type == .integer ? "a whole number" : field.type == .boolean ? "true or false" : "a \(field.type.rawValue)")."
        }
        if case .string(let s) = value, s.count > 1000 { return "is too long." }
        if case .number(let n) = value {
            if let lo = field.minimum, n < lo { return "should be at least \(lo.formatted())." }
            if let hi = field.maximum, n > hi { return "should be at most \(hi.formatted())." }
        }
        return nil
    }
}

/// Entry point for `sidefolk ext validate <dir>`.
public enum ExtensionValidator {
    public static func validate(at folder: URL, paths: SidefolkPaths = .standard(),
                                resolver: InterpreterResolver = .system) -> ValidationReport {
        ManifestValidator(paths: paths, resolver: resolver).validate(folder: folder, mode: .source)
    }
}
