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

        public init(extensionDir: String, dataDir: String, executable: String, reexec: String? = nil,
                    runtime: [String] = [], permissions: ExtensionPermissions, allowFork: Bool? = nil) {
            self.extensionDir = extensionDir
            self.dataDir = dataDir
            self.executable = executable
            self.reexec = reexec
            self.runtime = runtime
            self.permissions = permissions
            self.allowFork = allowFork
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
            sb += "\n;; power (granted at install): keep awake, declare activity\n(allow mach-lookup (global-name \"com.apple.PowerManagement.control\"))\n"
        }
        if inputs.permissions.media {
            sb += mediaRules
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
      (global-name "com.apple.system.logger")
      (global-name "com.apple.system.notification_center")
      (global-name "com.apple.system.opendirectoryd.libinfo")
      (global-name "com.apple.system.DirectoryService.libinfo_v1")
      (global-name "com.apple.cfprefsd.daemon") (global-name "com.apple.cfprefsd.agent")
      (global-name "com.apple.trustd.agent") (global-name "com.apple.logd")
      ;; free space as Finder and System Settings count it (what macOS can clear counts as free); read-only, and
      ;; open to every app in Apple's own App Sandbox
      (global-name "com.apple.cache_delete.public"))
    (allow ipc-posix-shm-read* (ipc-posix-name "apple.shm.notification_center"))

    ;; what dyld, libSystem and interpreters need
    (allow file-read-metadata)
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
    static let mediaRules = """

    ;; media (granted at install): the GPU and the decoders, nothing else
    (allow iokit-open (iokit-user-client-class "IOSurfaceRootUserClient" "AGXDeviceUserClient"))
    (allow mach-lookup (global-name "com.apple.coremedia.videodecoder"))

    """

    /// All-or-nothing: hosts can only be `*` or `localhost`, so a network extension also reaches the LAN.
    static let networkRules = """

    ;; network (granted at install)
    (allow system-socket)
    (allow network-outbound (remote ip "*:*"))
    (allow network-outbound (literal "/private/var/run/mDNSResponder"))
    (allow file-read* (subpath "/private/etc/ssl")
      (regex #"^/(opt/homebrew|usr/local)/etc/(ca-certificates|openssl(@[0-9.]+)?)/"))

    """
}
