import Foundation

/// A tool an extension or MCP server provides, registered as `ext.<short>.<tool>` with the extension id
/// as owner. Results are always untrusted; Guard scopes "always allow" grants to the extension.
public struct ExtensionTool: Tool {
    public let spec: ToolSpec
    public let extensionId: String
    public let extensionName: String
    /// The tool's name on the extension's side of the protocol.
    public let remoteName: String
    /// Parameters naming a folder the person chooses (`tools.<name>.paths`): Guard checks them like any
    /// file tool's paths, and the sandbox opens exactly those for this call.
    public let folderParameters: [String: ExtensionManifest.FolderUse]
    /// One of Sidefolk's own extensions (D39): its approval cards may say what a call does in a sentence.
    public let firstParty: Bool
    /// Sentences its manifest says call it without the AI (D50); nil when there are none.
    public let commands: ToolCommands?
    /// Its calls reach only a device the person paired, which its program confirms (D72); nil for everyone but
    /// Sidefolk's own extensions, whatever their manifest says: the sandbox can't hold a program to its word.
    public let paired: PairedDevice?
    private let invoke: @Sendable (JSONValue, [ExtensionFolderGrant]) async throws -> ToolResult

    /// A tool whose calls go to a device the person paired: the parameter that names it (nil: the device in use now),
    /// and how to ask the program which paired device a call would reach (`sidefolk/paired.check`).
    public struct PairedDevice: Sendable {
        public var parameter: String?
        public var check: @Sendable (JSONValue) async -> PairedAnswer?
    }

    /// Seconds a manifest may give one call (`tools.<name>.timeout`).
    public static let timeouts = 1...300

    init(spec: ToolSpec, extensionId: String, extensionName: String, remoteName: String,
         folderParameters: [String: ExtensionManifest.FolderUse] = [:], firstParty: Bool = false, commands: ToolCommands? = nil,
         paired: PairedDevice? = nil, invoke: @escaping @Sendable (JSONValue, [ExtensionFolderGrant]) async throws -> ToolResult) {
        self.spec = spec
        self.extensionId = extensionId
        self.extensionName = extensionName
        self.remoteName = remoteName
        self.folderParameters = folderParameters
        self.firstParty = firstParty
        self.commands = commands
        self.paired = firstParty ? paired : nil
        self.invoke = invoke
    }

    public static func registryName(short: String, tool: String) -> String { "ext.\(short).\(tool)" }

    /// MCP servers name tools freely (`getFileContents`, `git-status`); Sidefolk names are `[a-z0-9_]`.
    static func localName(_ remote: String, maxLength: Int) -> String? {
        var out = ""
        for ch in remote.lowercased() {
            out.append(ch.isASCII && (ch.isLetter || ch.isNumber) ? ch : "_")
        }
        let trimmed = String(out.prefix(maxLength)).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A built-in's call as a sentence (BuiltInToolSummary); anyone else's as its title and its exact arguments (T1).
    public func summary(for input: JSONValue) -> String {
        if firstParty, let sentence = BuiltInToolSummary.sentence(extensionId: extensionId, tool: remoteName, input: input) {
            return sentence
        }
        let args = (input.objectValue?.isEmpty ?? true) ? "" : " " + input.jsonString
        return "\(spec.title) (\(extensionName))\(args)"
    }

    public func scope(for input: JSONValue) -> ToolScope {
        var scope = ToolScope(extensionId: extensionId)
        // Only Sidefolk's own programs are taken at their word about where they go (D47).
        if firstParty, let service = BuiltInServices.byExtension[extensionId] { scope.reach = .service(service.name) }
        for (param, use) in folderParameters.sorted(by: { $0.key < $1.key }) {
            guard let raw = input.string(param), !raw.isEmpty else { continue }
            let path = (raw as NSString).expandingTildeInPath
            if use == .write { scope.writePaths.append(path) } else { scope.readPaths.append(path) }
        }
        return scope
    }

    /// Asks the program which paired device this call would reach, and binds the call to it: the parameter naming the
    /// device becomes that device's id, so what runs is what was confirmed, not whatever answers to the same name by
    /// then (D72). A tool that names no device may reach none at all (stopping what isn't running). Anything short of a
    /// clear answer leaves the scope as it was, and Guard asks as before.
    public func confirmReach(_ input: JSONValue, scope: ToolScope) async -> (scope: ToolScope, input: JSONValue) {
        // The program hears only the words naming the device: the rest of the call waits for Guard.
        let naming: JSONValue = .object(paired?.parameter.flatMap { p in input[p].map { [p: $0] } } ?? [:])
        guard let paired, let answer = await paired.check(naming), answer.paired else { return (scope, input) }
        var scope = scope
        if let parameter = paired.parameter {
            guard let device = answer.device else { return (scope, input) }
            scope.reach = .paired(device: device)
            return (scope, input.setting(parameter, .string(device)))
        }
        scope.reach = .paired(device: answer.device)
        return (scope, input)
    }

    /// A folder parameter must be a path Guard can check; a relative one would mean the extension's own folder.
    public func refusal(for input: JSONValue, context: ToolContext) -> String? {
        for param in folderParameters.keys.sorted() {
            guard let value = input[param], !value.isNull else { continue }
            guard let raw = value.stringValue, (raw as NSString).expandingTildeInPath.hasPrefix("/") else {
                return "“\(param)” must be a full path, like ~/git/project."
            }
        }
        return nil
    }

    /// Hands the call over with the folders Guard allowed for it, re-checked now: a folder replaced by a
    /// link since Guard looked resolves somewhere else and is refused. The extension receives each folder
    /// as the canonical path the sandbox opens (its `HOME` is its data folder, so `~` would mislead it).
    public func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        var input = input
        var grants: [ExtensionFolderGrant] = []
        for (param, use) in folderParameters.sorted(by: { $0.key < $1.key }) {
            guard let raw = input.string(param), !raw.isEmpty else { continue }
            let path = (raw as NSString).expandingTildeInPath
            let write = use == .write
            guard let canon = FolderAccess.canonical(path), FolderAccess.forbiddenReason([canon]) == nil,
                  FolderAccess.allows(canon, write: write, folders: context.folders) else {
                throw UserFacingError("\(FolderAccess.displayPath(path)) isn't shared with Sidefolk for this.", changedNothing: true)
            }
            grants.append(ExtensionFolderGrant(path: canon, write: write))
            input = input.setting(param, .string(canon))
        }
        return try await invoke(input, grants)
    }
}

/// What a program said about the device a call would reach (`sidefolk/paired.check`, D72): `paired` with the device's
/// id when it's one the person paired, `paired` with none when the call reaches no device, otherwise not paired.
public struct PairedAnswer: Sendable, Hashable {
    public var paired: Bool
    public var device: String?

    public init(paired: Bool, device: String? = nil) {
        self.paired = paired
        self.device = device
    }

    /// The program's reply, read strictly: anything unexpected is "not paired".
    static func parse(_ reply: JSONValue) -> PairedAnswer {
        guard case .bool(true)? = reply["paired"] else { return PairedAnswer(paired: false) }
        guard let raw = reply["device"], !raw.isNull else { return PairedAnswer(paired: true) }
        guard let device = raw.stringValue, (1...128).contains(device.count),
              device.range(of: #"^[A-Za-z0-9._:-]+$"#, options: .regularExpression) != nil else { return PairedAnswer(paired: false) }
        return PairedAnswer(paired: true, device: device)
    }
}

/// A folder the sandbox opens for one call, already checked by Guard against the person's shared folders.
public struct ExtensionFolderGrant: Sendable, Hashable {
    public var path: String
    public var write: Bool
}
