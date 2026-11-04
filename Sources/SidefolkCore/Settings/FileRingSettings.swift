import Foundation

/// The ring of what a file can become (D152).
public struct FileRingSettings: Codable, Sendable, Equatable {
    /// The key held during a drag to open it.
    public enum DragKey: String, Codable, Sendable, CaseIterable {
        case option, control, shift, command
    }

    public var enabled = false
    public var dragKey = DragKey.option

    public init() {}

    private enum CodingKeys: String, CodingKey { case enabled, dragKey }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? false
        dragKey = (try? c.decode(DragKey.self, forKey: .dragKey)) ?? .option
    }
}
