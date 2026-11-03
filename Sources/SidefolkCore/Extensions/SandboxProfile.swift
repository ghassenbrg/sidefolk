import Foundation

/// The `sandbox-exec` profile for one extension (SECURITY §3). Every path reaches the profile only as a
/// `-D KEY=value` parameter, never spliced into SBPL, and the builder emits exactly one rule per
/// parameter it supplies (a referenced but missing parameter fails profile compilation). All values are
/// `realpath`s: `/tmp/…` instead of `/private/tmp/…` silently matches nothing.
public struct SandboxProfile: Sendable, Hashable {
    public struct Parameter: Sendable, Hashable {
        public var key: String
        public var value: String
    }

    public var text: String
    public var parameters: [Parameter]

    /// `-D KEY=value` pairs for `sandbox-exec`, in order.
    public var arguments: [String] { parameters.flatMap { ["-D", "\($0.key)=\($0.value)"] } }

    /// Mach services a specific system program needs; granted only when that program is in the exec
    /// list (and so already named on the install sheet). `pmset -g batt` asks powerd for battery state.
    public static let servicesForExec: [String: [String]] = [
        "/usr/bin/pmset": ["com.apple.PowerManagement.control"],
    ]

    public struct Inputs: Sendable {
        public var extensionDir: String
        public var dataDir: String
        /// The binary the sandbox starts (interpreter or the extension's own program).
        public var executable: String
        public var reexec: String?
        public var runtime: [String]
        public var permissions: ExtensionPermissions
        /// Whether the extension may create processes. Nil means: only when the manifest lists
        /// programs to run (`exec`), which the install sheet names. Without fork, an extension can't
        /// leave a process behind (SECURITY T15).
        public var allowFork: Bool?
        /// The folder holding every extension's data folder, which this one mustn't see into.
        public var allData: String?

        public init(extensionDir: String, dataDir: String, executable: String, reexec: String? = nil,
                    runtime: [String] = [], permissions: ExtensionPermissions, allowFork: Bool? = nil, allData: String? = nil) {
            self.extensionDir = extensionDir
            self.dataDir = dataDir
            self.executable = executable
            self.reexec = reexec
            self.runtime = runtime
            self.permissions = permissions
            self.allowFork = allowFork
            self.allData = allData
        }
    }

    /// Builds the profile; paths that don't canonicalise are an error.
    public static func make(_ inputs: Inputs) throws -> SandboxProfile {
        func real(_ path: String) throws -> String {
            guard let canon = FolderAccess.canonical(path) else {
                throw UserFacingError("The extension's sandbox couldn't use \(path).")
            }
            return canon
        }
        var params: [Parameter] = []
        func add(_ key: String, _ value: String) -> String {
            params.append(Parameter(key: key, value: value))
            return "(param \"\(key)\")"
        }

        var sb = baseRules
        // Programs named by the manifest (git) load from their own installation, like an interpreter does.
        var runtimeFolders: [String] = []
        for folder in inputs.runtime + inputs.permissions.programs.flatMap(\.runtime) where !runtimeFolders.contains(folder) {
            runtimeFolders.append(folder)
        }
        let runtime = try runtimeFolders.map(real)
        if !runtime.isEmpty {
            sb += "\n;; interpreter runtime (read-only)\n(allow file-read* file-map-executable\n"
            sb += runtime.enumerated().map { "  (subpath \(add("RT_\($0.offset)", $0.element)))" }.joined(separator: "\n") + ")\n"
        }

        sb += "\n;; the extension (read-only) and its data folder (read-write)\n"
        sb += "(allow file-read* (subpath \(add("EXT_DIR", try real(inputs.extensionDir)))))\n"
        sb += "(allow file-read* file-write* (subpath \(add("DATA_DIR", try real(inputs.dataDir)))))\n"
        // What's inside is the program's; the folder itself is Sidefolk's.
        sb += "(deny file-write-unlink file-write-create (literal (param \"DATA_DIR\")))\n"
        let allData = try inputs.allData.map { add("ALL_DATA", try real($0)) }

        let reads = try inputs.permissions.read.map(real)
        if !reads.isEmpty {
            sb += "\n;; files.read\n(allow file-read*\n"
            sb += reads.enumerated().map { "  (subpath \(add("READ_\($0.offset)", $0.element)))" }.joined(separator: "\n") + ")\n"
        }
        let writes = try inputs.permissions.write.map(real)
        if !writes.isEmpty {
            sb += "\n;; files.write\n(allow file-read* file-write*\n"
            sb += writes.enumerated().map { "  (subpath \(add("WRITE_\($0.offset)", $0.element)))" }.joined(separator: "\n") + ")\n"
        }

        sb += "\n;; exec allow-list: the program (+ the binary it re-executes) and the manifest's exec entries\n(allow process-exec\n"
        var execs = ["  (literal \(add("RUN_EXEC", try real(inputs.executable))))"]
        if let reexec = inputs.reexec { execs.append("  (literal \(add("RUN_EXEC_2", try real(reexec))))") }
        var listed = inputs.permissions.exec
        for program in inputs.permissions.programs {
            for path in [program.path] + program.helpers where !listed.contains(path) { listed.append(path) }
        }
        let exec = try listed.map(real)
        execs += exec.enumerated().map { "  (literal \(add("EXEC_\($0.offset)", $0.element)))" }
        sb += execs.joined(separator: "\n") + ")\n"

        if inputs.allowFork ?? !exec.isEmpty {
            sb += "\n;; new processes (it runs programs; children inherit this sandbox)\n(allow process-fork)\n"
        }

        let services = exec.flatMap { servicesForExec[$0] ?? [] }
        if !services.isEmpty {
            sb += "\n;; services the listed programs need\n(allow mach-lookup\n"
            sb += services.enumerated().map { "  (global-name \(add("MACH_\($0.offset)", $0.element)))" }.joined(separator: "\n") + ")\n"
        }

        if inputs.permissions.network {
            sb += networkRules
        }
        if inputs.permissions.clipboard {
            sb += "\n;; clipboard (granted at install)\n(allow mach-lookup (global-name \"com.apple.pasteboard.1\"))\n"
        }
        if inputs.permissions.power {
            sb += "\n;; power (granted at install): hold off sleep, declare activity\n(allow mach-lookup (global-name \"com.apple.PowerManagement.control\"))\n"
        }
        if inputs.permissions.media {
            sb += mediaRules
        }
        if inputs.permissions.screen {
            sb += screenRules
        }
        if inputs.permissions.network && inputs.permissions.udp {
            sb += udpRules
        }
        // People's folders are denied in the base rules, and a `file-read*` doesn't undo that (measured), so what it was given
        // opens by name here. Above each of those, only the folder itself: the way down, and no further. All of it twice, because
        // the same folders also go by the data volume's own name, which `F_GETPATH_NOFIRMLINK` can hand back.
        let dataVolume = "/System/Volumes/Data"
        var ways: Set<String> = ["/Users", NSHomeDirectory()]
        let given = params.filter { $0.key != "ALL_DATA" && $0.value.hasPrefix("/Users/") }
        for path in params.map(\.value) where path.hasPrefix("/Users/") {
            var up = (path as NSString).deletingLastPathComponent
            while up != "/" {
                ways.insert(up)
                up = (up as NSString).deletingLastPathComponent
            }
        }
        sb += "\n;; what it was given, and the folders above that, by name only\n(allow file-read-metadata file-test-existence\n"
        for (index, path) in given.enumerated() {
            sb += "  (subpath (param \"\(path.key)\"))\n  (subpath \(add("GIVEN_\(index)", dataVolume + path.value)))\n"
        }
        let everyWay = ways.union(ways.map { dataVolume + $0 }).sorted()
        sb += everyWay.enumerated().map { "  (literal \(add("WAY_\($0.offset)", $0.element)))" }.joined(separator: "\n") + ")\n"
        // Everything else's data stays out of sight, whatever was given above it: even when a file changed is no business of
        // another extension's. Last, so nothing opened here undoes it. Reading the folder itself would list who is installed.
        if let allData {
            let other = add("ALL_DATA_VOLUME", dataVolume + (params.first { $0.key == "ALL_DATA" }?.value ?? ""))
            let mine = add("DATA_DIR_VOLUME", dataVolume + (params.first { $0.key == "DATA_DIR" }?.value ?? ""))
            sb += "(deny file-read-metadata file-test-existence (subpath \(allData)) (subpath \(other)))\n"
            sb += "(allow file-read-metadata file-test-existence (literal \(allData)) (literal \(other)) (subpath (param \"DATA_DIR\")) (subpath \(mine)))\n"
            sb += "(deny file-read-data (literal \(allData)) (literal \(other)))\n"
        }
        return SandboxProfile(text: sb, parameters: params)
    }

    static let baseRules = """
    (version 1)
    (deny default)

    ;; process basics (fork only when the manifest lists programs to run)
    (allow signal (target same-sandbox))
    (allow sysctl-read)
    (allow mach-lookup
      (global-name "com.apple.system.opendirectoryd.libinfo")
      (global-name "com.apple.system.DirectoryService.libinfo_v1")
      (global-name "com.apple.cfprefsd.daemon") (global-name "com.apple.cfprefsd.agent")
      (global-name "com.apple.logd")
      ;; free space as Finder and System Settings count it (what macOS can clear counts as free); read-only, and
      ;; open to every app in Apple's own App Sandbox
      (global-name "com.apple.cache_delete.public"))

    ;; what dyld, libSystem and interpreters need
    (allow file-read-metadata)
    ;; nothing in people's folders can be seen by name or looked up by a file's number (fsgetpath); what it's given opens below
    (deny file-read-metadata file-test-existence (subpath "/Users") (subpath "/System/Volumes/Data/Users"))
    (allow file-read*
      (literal "/")
      (subpath "/usr/lib") (subpath "/usr/share") (subpath "/System") (subpath "/Library/Apple")
      (subpath "/private/var/db/timezone") (literal "/private/etc/localtime")
      (literal "/private/etc/passwd") (literal "/private/etc/services") (literal "/private/etc/protocols")
      (literal "/private/var/select/sh")
      (literal "/dev/null") (literal "/dev/zero") (literal "/dev/random") (literal "/dev/urandom")
      (subpath "/dev/fd"))
    (allow file-map-executable (subpath "/usr/lib") (subpath "/System") (subpath "/Library/Apple"))
    (allow file-write-data (literal "/dev/null") (literal "/dev/zero"))
    ;; OpenSSL's settings, which Homebrew's node reads at start with or without the internet: only
    ;; that file, for any OpenSSL version, under either Homebrew prefix.
    (allow file-read* (regex #"^/(opt/homebrew|usr/local)/etc/openssl(@[0-9.]+)?/openssl\\.cnf$"))

    """

    /// Image work on Apple silicon: Core Image renders on the GPU even when asked for its software renderer, and
    /// ImageIO reads a photo the hardware decoded through the video decoder service. Two user clients and one
    /// service, measured on macOS 27 (resize, HEIC/PNG/JPEG out, a QR code drawn and read); no files, no network.
    /// HEIC and AVIF out need trustd too: the video encoder is chosen only after its signature is checked. That service can
    /// fetch from an address a certificate names, so what `media` allows isn't sealed off from the internet (PermissionSummary).
    /// Core Audio finds its codecs through the registrar, or writing compressed or 24-bit sound fails (D143).
    static let mediaRules = """

    ;; media (granted at install): the GPU, the decoders and the audio codecs, nothing else
    (allow iokit-open (iokit-user-client-class "IOSurfaceRootUserClient" "AGXDeviceUserClient"))
    (allow mach-lookup (global-name "com.apple.coremedia.videodecoder") (global-name "com.apple.trustd.agent")
      (global-name "com.apple.audio.AudioComponentRegistrar"))

    """

    /// ScreenCaptureKit and the hardware encoder, measured on macOS 27 (displays and windows listed, a picture taken,
    /// the screen and the Mac's sound streamed, then H.264 from VideoToolbox): replayd, the window server, and the
    /// encoder service. Nothing more: no Launch Services, no pasteboard, no Dock. macOS still asks the person, for
    /// Sidefolk, since the extension runs as Sidefolk's child (D69). Pictures in IOSurfaces need `media` too.
    static let screenRules = """

    ;; screen (granted at install): ScreenCaptureKit, and the video encoder for what it records
    (allow mach-lookup (global-name "com.apple.replayd") (global-name "com.apple.windowserver.active")
      (global-name "com.apple.coremedia.videoencoder"))

    """

    /// What WebRTC's media needs beyond going out: a UDP port of its own and the packets that come back to it,
    /// measured on macOS 27 (`network` alone refuses the bind). TCP stays outbound only: no listening server.
    static let udpRules = """

    ;; udp (granted at install, with network): live audio and video
    (allow network-bind (local udp "*:*"))
    (allow network-inbound (local udp "*:*"))

    """

    /// All-or-nothing: hosts can only be `*` or `localhost`, so a network extension also reaches the LAN.
    static let networkRules = """

    ;; network (granted at install)
    (allow system-socket)
    (allow network-outbound (remote ip "*:*"))
    (allow network-outbound (literal "/private/var/run/mDNSResponder"))
    ;; checking a server's certificate needs this service, which can itself fetch from an address a certificate names
    (allow mach-lookup (global-name "com.apple.trustd.agent"))
    (allow file-read* (subpath "/private/etc/ssl")
      (regex #"^/(opt/homebrew|usr/local)/etc/(ca-certificates|openssl(@[0-9.]+)?)/"))

    """
}
