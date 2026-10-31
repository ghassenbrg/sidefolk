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
    /// The icon file, when the manifest names one that passed the checks.
    public var iconPath: String?

    public var isValid: Bool { errors.isEmpty && manifest != nil && launch != nil && permissions != nil }

    /// Effective risk of each declared tool after Sidefolk's floors.
    public var toolRisks: [(name: String, risk: Risk)] {
        guard let manifest, let permissions else { return [] }
        return manifest.tools.keys.sorted().map { name in
            (name, ExtensionRisk.effective(declared: manifest.tools[name]?.risk, permissions: permissions, kind: .sidefolk))
        }
    }

    /// Each tool's commands, as "tool: “time in …”, “what time is it in …”", with "(not for the AI)" when the AI
    /// never sees the tool.
    public var commandLines: [String] {
        guard let manifest else { return [] }
        return manifest.tools.keys.sorted().compactMap { name in
            guard let meta = manifest.tools[name], let commands = ToolCommands(meta.commands, words: manifest.words) else { return nil }
            let said = commands.shown.map { "“\($0)”" }.joined(separator: ", ")
            return "\(name): \(said)" + (meta.offeredToModel ? "" : " (not for the AI)")
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
        if let icon = manifest?.icon, iconPath != nil { out.append("Icon: \(icon)") }
        if let summary {
            out.append("Permissions:")
            out += summary.texts.map { "  - \($0)" }
        }
        let risks = toolRisks
        if !risks.isEmpty { out.append("Tools: " + risks.map { "\($0.name) (\($0.risk.rawValue))" }.joined(separator: ", ")) }
        if let m = manifest, !m.watchers.isEmpty { out.append("Watchers: " + m.watchers.keys.sorted().joined(separator: ", ")) }
        if let m = manifest, !m.pages.isEmpty { out.append("Pages: " + m.pages.keys.sorted().compactMap { m.pages[$0]?.title }.joined(separator: ", ")) }
        if let m = manifest, !m.palettes.isEmpty {
            out.append("Palettes: " + m.palettes.keys.sorted().compactMap { k in m.palettes[k].map { "\($0.title)\($0.hotkey.map { " (\($0))" } ?? "")" } }
                .joined(separator: ", "))
        }
        if let m = manifest, !m.games.isEmpty { out.append("Games: " + m.games.keys.sorted().compactMap { m.games[$0]?.title }.joined(separator: ", ")) }
        if manifest?.background == true { out.append("Keeps running while it's on") }
        let commands = commandLines
        if !commands.isEmpty {
            out.append("Answers without AI (D50):")
            out += commands.map { "  - \($0)" }
        }
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
    public var programs: ProgramResolver

    public init(paths: SidefolkPaths, resolver: InterpreterResolver = .system, programs: ProgramResolver = .system) {
        self.paths = paths
        self.resolver = resolver
        self.programs = programs
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
        report.iconPath = checkIcon(manifest.icon, folder: dir, issues: &issues)
        var permissions = checkPermissions(manifest.permissions, folder: dir, issues: &issues, warnings: &report.warnings)
        permissions.folders = checkTools(manifest, issues: &issues)
        issues += ExtensionCommandRules.check(manifest)
        report.permissions = permissions
        checkWatchers(manifest, issues: &issues)
        checkPages(manifest, issues: &issues)
        checkPalettes(manifest, issues: &issues)
        checkGames(manifest, issues: &issues)
        report.summary = PermissionSummary.forExtension(permissions)
        report.errors = issues
        return report
    }

    // MARK: Identity

    /// The name a source folder goes by. A gallery pack is unpacked as `<name>.sidefolkaddon/Contents/Resources`
    /// (D55), so its name is the bundle's, not "Resources".
    static func sourceName(_ folder: String) -> String {
        let parts = (folder as NSString).pathComponents
        if parts.count >= 3, parts[parts.count - 1] == "Resources", parts[parts.count - 2] == "Contents",
           parts[parts.count - 3].hasSuffix(".sidefolkaddon") {
            return (parts[parts.count - 3] as NSString).deletingPathExtension
        }
        return (folder as NSString).lastPathComponent
    }

    private func checkIdentity(_ m: ExtensionManifest, folder: String, mode: Mode, issues: inout [ValidationIssue], warnings: inout [String]) {
        if m.id.count > 64 || m.id.range(of: Self.idPattern, options: .regularExpression) == nil {
            issues.append(ValidationIssue(field: "id", message: "must look like com.example.my-extension (lowercase, at least one dot, at most 64 characters)."))
        }
        let folderName = mode == .installed ? (folder as NSString).lastPathComponent : Self.sourceName(folder)
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
        if let t = m.tagline, t.isEmpty || t.count > 60 || t.contains(where: \.isNewline) || ExtensionText.clean(t) != t {
            issues.append(ValidationIssue(field: "tagline", message: "must be one line of 1–60 characters of plain text."))
        }
        if let a = m.author, a.count > 100 || ExtensionText.clean(a) != a {
            issues.append(ValidationIssue(field: "author", message: "must be at most 100 characters of plain text."))
        }
        if let f = m.folk, f.range(of: #"^[a-z0-9-]{1,32}$"#, options: .regularExpression) == nil {
            issues.append(ValidationIssue(field: "folk", message: "must be a folk name like byte."))
        }
        if let req = m.sidefolk {
            switch Self.satisfies(req, current: SidefolkVersion.current) {
            case nil: issues.append(ValidationIssue(field: "sidefolk", message: "must look like >=0.1."))
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

    // MARK: Icon

    /// The icon's real path when it is a PNG or PDF inside the folder that passes `ExtensionIcon`'s checks.
    private func checkIcon(_ icon: String?, folder: String, issues: inout [ValidationIssue]) -> String? {
        guard let icon else { return nil }
        guard ExtensionIcon.fileTypes.contains((icon as NSString).pathExtension.lowercased()) else {
            issues.append(ValidationIssue(field: "icon", message: "must be a .png or .pdf file (SVG isn't accepted; export it as PDF)."))
            return nil
        }
        guard let rel = insidePath(icon, folder: folder, field: "icon", executable: false, issues: &issues) else { return nil }
        let path = folder + "/" + rel
        guard let st = ExtensionFS.lstat(path), Int(st.st_size) <= ExtensionIcon.maxBytes else {
            issues.append(ValidationIssue(field: "icon", message: "“\(icon)” is larger than 256 KiB."))
            return nil
        }
        guard let data = FileManager.default.contents(atPath: path) else {
            issues.append(ValidationIssue(field: "icon", message: "“\(icon)” couldn't be read."))
            return nil
        }
        if let problem = ExtensionIcon.problem(data, fileName: rel) {
            issues.append(ValidationIssue(field: "icon", message: "“\(icon)” \(problem)"))
            return nil
        }
        return path
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
        var result = ExtensionPermissions(network: p.network, media: p.media, clipboard: p.clipboard, power: p.power, screen: p.screen,
                                          udp: p.udp && p.network)
        if let purpose = p.networkPurpose {
            let line = ExtensionText.line(purpose, characters: 120)
            if !p.network || line != purpose || !purpose.hasPrefix("for ") && !purpose.hasPrefix("to ") {
                issues.append(ValidationIssue(field: "permissions.network_purpose",
                                              message: "must come with permissions.network and be one plain line of at most 120 characters starting with “to” or “for”."))
            } else {
                result.networkPurpose = purpose
            }
        }
        if p.udp && !p.network {
            issues.append(ValidationIssue(field: "permissions.udp", message: "needs permissions.network: UDP is part of using the network."))
        }
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
            if !raw.contains("/"), ProgramResolver.known[raw] != nil {
                guard let program = programs.resolve(raw) else {
                    issues.append(ValidationIssue(field: field, message: "\(raw) isn't installed on this Mac. Install Apple's command line tools with xcode-select --install, or \(raw) with Homebrew."))
                    continue
                }
                if !result.programs.contains(where: { $0.name == program.name }) { result.programs.append(program) }
                continue
            }
            guard raw.hasPrefix("/"), !ExtensionText.hasControlOrQuote(raw) else {
                let named = ProgramResolver.known.keys.sorted().joined(separator: ", ")
                issues.append(ValidationIssue(field: field, message: "must be an absolute path like /usr/bin/pmset, or a program Sidefolk finds by name (\(named))."))
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

    /// Returns the most any tool does in a folder named in a call (`write` over `read`), for the permission sheet.
    private func checkTools(_ m: ExtensionManifest, issues: inout [ValidationIssue]) -> ExtensionManifest.FolderUse? {
        if m.tools.count > 128 { issues.append(ValidationIssue(field: "tools", message: "can declare at most 128 tools.")) }
        var folders: ExtensionManifest.FolderUse?
        for name in m.tools.keys.sorted() {
            let field = "tools.\(name)"
            if name.range(of: Self.namePattern, options: .regularExpression) == nil {
                issues.append(ValidationIssue(field: field, message: "isn't a valid tool name (lowercase letters, digits and _)."))
            } else if ExtensionTool.registryName(short: m.shortName, tool: name).count > 64 {
                issues.append(ValidationIssue(field: field, message: "makes the full tool name ext.\(m.shortName).\(name) longer than 64 characters."))
            }
            guard let meta = m.tools[name] else { continue }
            if let t = meta.title, t.isEmpty || t.count > 80 || ExtensionText.clean(t) != t {
                issues.append(ValidationIssue(field: "\(field).title", message: "must be 1–80 characters of plain text."))
            }
            if let t = meta.timeout, !ExtensionTool.timeouts.contains(t) {
                issues.append(ValidationIssue(field: "\(field).timeout", message: "must be between 1 and 300 seconds."))
            }
            if let device = meta.device {
                if meta.reach == nil {
                    issues.append(ValidationIssue(field: "\(field).device", message: "needs \"reach\": \"paired\"."))
                } else if device.range(of: Self.namePattern, options: .regularExpression) == nil || meta.paths[device] != nil {
                    issues.append(ValidationIssue(field: "\(field).device", message: "isn't a valid parameter name (lowercase letters, digits and _), or names a path."))
                }
            }
            if meta.paths.count > 4 { issues.append(ValidationIssue(field: "\(field).paths", message: "can name at most 4 parameters.")) }
            for (param, use) in meta.paths.sorted(by: { $0.key < $1.key }) {
                if param.range(of: Self.namePattern, options: .regularExpression) == nil {
                    issues.append(ValidationIssue(field: "\(field).paths.\(param)", message: "isn't a valid parameter name (lowercase letters, digits and _)."))
                }
                if use == .write || folders == nil { folders = use }
            }
        }
        return folders
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

extension ManifestValidator {
    static let symbolPattern = #"^[a-z0-9]+(\.[a-z0-9]+)*$"#
    /// `shift+cmd+v`: at least one of cmd, ctrl or option, then one key.
    static let hotkeyPattern = #"^((cmd|ctrl|option|shift)\+)*(cmd|ctrl|option)\+((cmd|ctrl|option|shift)\+)*([a-z0-9]|space|f[1-9]|f1[0-2])$"#

    func checkPalettes(_ m: ExtensionManifest, issues: inout [ValidationIssue]) {
        if m.palettes.count > 2 { issues.append(ValidationIssue(field: "palettes", message: "can declare at most 2 palettes.")) }
        for name in m.palettes.keys.sorted() {
            let field = "palettes.\(name)"
            guard let p = m.palettes[name] else { continue }
            if name.range(of: Self.namePattern, options: .regularExpression) == nil {
                issues.append(ValidationIssue(field: field, message: "isn't a valid palette name (lowercase letters, digits and _)."))
            }
            if p.title.isEmpty || p.title.count > 40 || ExtensionText.clean(p.title) != p.title {
                issues.append(ValidationIssue(field: "\(field).title", message: "must be 1–40 characters of plain text."))
            }
            if let h = p.hotkey, h.range(of: Self.hotkeyPattern, options: .regularExpression) == nil {
                issues.append(ValidationIssue(field: "\(field).hotkey", message: "must look like shift+cmd+v (cmd, ctrl or option, then one key)."))
            }
            if let ph = p.placeholder, ph.count > 60 || ExtensionText.clean(ph) != ph {
                issues.append(ValidationIssue(field: "\(field).placeholder", message: "must be at most 60 characters of plain text."))
            }
        }
    }

    /// Games (D75): a title, a symbol, levels, and sentences that follow the command rules (D50) with no slots, since
    /// a sentence only opens the game.
    func checkGames(_ m: ExtensionManifest, issues: inout [ValidationIssue]) {
        if m.games.count > 16 { issues.append(ValidationIssue(field: "games", message: "can declare at most 16 games.")) }
        var seen: [String: String] = [:]
        for name in m.games.keys.sorted() {
            let field = "games.\(name)"
            guard let g = m.games[name] else { continue }
            if name.range(of: Self.namePattern, options: .regularExpression) == nil || name.count > 32 {
                issues.append(ValidationIssue(field: field, message: "isn't a valid game name (lowercase letters, digits and _, at most 32)."))
            }
            if g.title.isEmpty || g.title.count > 40 || ExtensionText.clean(g.title) != g.title {
                issues.append(ValidationIssue(field: "\(field).title", message: "must be 1–40 characters of plain text."))
            }
            if let s = g.symbol, s.count > 64 || s.range(of: Self.symbolPattern, options: .regularExpression) == nil {
                issues.append(ValidationIssue(field: "\(field).symbol", message: "must be an SF Symbol name, like gamecontroller."))
            }
            if g.levels.count > 5 || Set(g.levels).count != g.levels.count
                || g.levels.contains(where: { $0.range(of: #"^[a-z][a-z0-9_]{0,19}$"#, options: .regularExpression) == nil }) {
                issues.append(ValidationIssue(field: "\(field).levels", message: "must be at most 5 different names of lowercase letters, digits and _."))
            }
            if g.say.count > ExtensionCommandRules.maxSentencesPerCommand {
                issues.append(ValidationIssue(field: "\(field).say", message: "can hold at most \(ExtensionCommandRules.maxSentencesPerCommand) sentences."))
            }
            for (i, sentence) in g.say.enumerated() {
                let sf = "\(field).say[\(i)]"
                do {
                    let compiled = try CommandSentence(sentence)
                    if !compiled.slots.isEmpty {
                        issues.append(ValidationIssue(field: sf, message: "can't have slots: a game's sentence only opens it."))
                    } else if let other = seen[compiled.shape] {
                        issues.append(ValidationIssue(field: sf, message: "says the same as \(other)."))
                    } else {
                        seen[compiled.shape] = sf
                    }
                } catch {
                    issues.append(ValidationIssue(field: sf, message: error.message))
                }
            }
        }
    }

    func checkPages(_ m: ExtensionManifest, issues: inout [ValidationIssue]) {
        if m.pages.count > 4 { issues.append(ValidationIssue(field: "pages", message: "can declare at most 4 pages.")) }
        for name in m.pages.keys.sorted() {
            let field = "pages.\(name)"
            guard let p = m.pages[name] else { continue }
            if name.range(of: Self.namePattern, options: .regularExpression) == nil {
                issues.append(ValidationIssue(field: field, message: "isn't a valid page name (lowercase letters, digits and _)."))
            }
            if p.title.isEmpty || p.title.count > 40 || ExtensionText.clean(p.title) != p.title {
                issues.append(ValidationIssue(field: "\(field).title", message: "must be 1–40 characters of plain text."))
            }
            if let s = p.symbol, s.count > 64 || s.range(of: Self.symbolPattern, options: .regularExpression) == nil {
                issues.append(ValidationIssue(field: "\(field).symbol", message: "must be an SF Symbol name, like gauge.with.dots.needle.67percent."))
            }
            if let r = p.refresh, !ExtensionManifest.PageMeta.refreshes.contains(r) {
                issues.append(ValidationIssue(field: "\(field).refresh", message: "must be between 2 and 3600 seconds."))
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

    /// What starting the program said.
    public struct TrialReport: Sendable {
        /// Registered tool names, as the model would see them.
        public var tools: [String]
        /// Where the manifest and the program's `tools/list` disagree.
        public var warnings: [String]
        /// Why it didn't start (exit status, its last stderr line), nil when it did.
        public var problem: String?

        public var text: String {
            if let problem { return "It didn't start.\n\(problem)" }
            var lines = ["It started in its sandbox and offers \(tools.count) tool\(tools.count == 1 ? "" : "s"): \(tools.joined(separator: ", "))."]
            lines += warnings.map { "Warning: \($0)" }
            return lines.joined(separator: "\n")
        }
    }

    /// Installs a copy into a throwaway Sidefolk home and starts it exactly as Sidefolk would: in its
    /// sandbox, `initialize` then `tools/list`. Nothing of the user's is read or changed.
    public static func trial(at folder: URL, resolver: InterpreterResolver = .system) async -> TrialReport {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-ext-trial-\(UUID().uuidString)", isDirectory: true)
        defer { ExtensionFiles.removeTree(home.path) }
        do {
            let paths = SidefolkPaths(home: home)
            try paths.prepare()
            var configuration = ExtensionHost.Configuration()
            configuration.resolver = resolver
            let host = ExtensionHost(paths: paths, store: ExtensionStore(try AppDatabase.inMemory()), registry: ToolRegistry(),
                                     events: EventBus(), configuration: configuration)
            let info = try await host.install(from: folder)
            await host.shutdown()
            return TrialReport(tools: info.tools.map(\.name), warnings: info.toolWarnings, problem: nil)
        } catch let e as UserFacingError {
            return TrialReport(tools: [], warnings: [], problem: [e.message, e.recovery, e.detail].compactMap { $0 }.joined(separator: "\n"))
        } catch {
            return TrialReport(tools: [], warnings: [], problem: String(describing: error))
        }
    }
}
