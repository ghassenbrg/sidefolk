import Foundation

public struct FrontmostApp: Sendable, Hashable {
    public var name: String
    public var bundleId: String?
    public var isFullscreen: Bool
    public init(name: String, bundleId: String?, isFullscreen: Bool = false) {
        self.name = name
        self.bundleId = bundleId
        self.isFullscreen = isFullscreen
    }
}

/// Mac services that need AppKit. The app provides the real implementation; tests use `NullPlatform`.
public protocol PlatformBridge: Sendable {
    func clipboardText() async -> String?
    func setClipboard(_ text: String) async
    /// Opens a URL with its default handler. Returns false if nothing could open it.
    func open(url: URL) async -> Bool
    /// Opens an application by name ("Safari") or bundle identifier.
    func openApplication(_ nameOrBundleId: String) async -> Bool
    func reveal(path: String) async
    func frontmostApplication() async -> FrontmostApp?
    /// Brings a running app to the front (by pid, else by bundle id). Returns false if it isn't running.
    func activateApplication(pid: Int?, bundleId: String?) async -> Bool
    func calendarEvents(from: Date, to: Date) async -> [CalendarEvent]?
}

public extension PlatformBridge {
    func activateApplication(pid: Int?, bundleId: String?) async -> Bool { false }
    /// The person's calendar events overlapping the range (D57); nil where there is none, or macOS doesn't allow it.
    /// Never asks macOS: only the person's own choice does, in the app.
    func calendarEvents(from: Date, to: Date) async -> [CalendarEvent]? { nil }
}

/// A platform that does nothing; used in tests and command-line contexts.
public struct NullPlatform: PlatformBridge {
    public init() {}
    public func clipboardText() async -> String? { nil }
    public func setClipboard(_ text: String) async {}
    public func open(url: URL) async -> Bool { false }
    public func openApplication(_ nameOrBundleId: String) async -> Bool { false }
    public func reveal(path: String) async {}
    public func frontmostApplication() async -> FrontmostApp? { nil }
    public func activateApplication(pid: Int?, bundleId: String?) async -> Bool { false }
}
