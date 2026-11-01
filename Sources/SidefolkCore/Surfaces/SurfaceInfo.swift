import Foundation
import Synchronization

/// A surface an extension declares (`surfaces` in its manifest, D99): the panel or overlay Sidefolk frames for it.
public struct SurfaceInfo: Sendable, Hashable, Identifiable {
    public enum Presentation: String, Sendable, Hashable, Decodable { case panel, overlay }

    public var extensionId: String
    public var extensionName: String
    public var surface: String
    public var title: String
    public var symbol: String?
    public var presentation: Presentation
    /// The canvas it asks for, within `SurfaceLimits`.
    public var width: Double
    public var height: Double
    public var say: [String]
    public var ai: Bool
    /// Its pack has sounds, so the frame offers the speaker.
    public var sounds: Bool
    public var iconPath: String?

    public init(extensionId: String, extensionName: String, surface: String, title: String, symbol: String? = nil,
                presentation: Presentation = .panel, width: Double = 400, height: Double = 480, say: [String] = [], ai: Bool = false,
                sounds: Bool = false, iconPath: String? = nil) {
        self.extensionId = extensionId
        self.extensionName = extensionName
        self.surface = surface
        self.title = title
        self.symbol = symbol
        self.presentation = presentation
        self.width = width
        self.height = height
        self.say = say
        self.ai = ai
        self.sounds = sounds
        self.iconPath = iconPath
    }

    public var id: String { "\(extensionId)/\(surface)" }
}

/// A surface to open, and whether it takes the keyboard: it does when the person asked (their words, a menu), and waits
/// for a click when the AI did (D75's rule). An overlay never takes it.
public struct SurfaceRequest: Sendable, Hashable {
    public var info: SurfaceInfo
    public var focus: Bool
    public var arguments: [String: JSONValue]

    public init(info: SurfaceInfo, focus: Bool = true, arguments: [String: JSONValue] = [:]) {
        self.info = info
        self.focus = focus
        self.arguments = arguments
    }

    public var takesKeyboard: Bool { focus && info.presentation == .panel }
}

/// The surfaces of enabled extensions, where the sentence matcher and the tool can read them at once.
public final class SurfaceShelf: Sendable {
    private let surfaces = Mutex<[SurfaceInfo]>([])
    public init() {}
    public var all: [SurfaceInfo] { surfaces.withLock { $0 } }
    func set(_ list: [SurfaceInfo]) { surfaces.withLock { $0 = list } }
}
