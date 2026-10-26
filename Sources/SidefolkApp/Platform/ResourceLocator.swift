import Foundation
import SidefolkCore

/// Finds bundled resources: inside the app bundle, or in the repository when running a dev build
/// outside a bundle (`SIDEFOLK_RESOURCES` overrides both).
enum ResourceLocator {
    static var resources: URL? {
        if let custom = ProcessInfo.processInfo.environment["SIDEFOLK_RESOURCES"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        if let url = Bundle.main.resourceURL, FileManager.default.fileExists(atPath: url.appendingPathComponent("Skills").path) {
            return url
        }
        return nil
    }

    /// Sample extensions shipped with the app, offered in Settings › Extensions.
    static var sampleExtensions: URL? { resources?.appendingPathComponent("Extensions", isDirectory: true) }

    /// One folder of pose images per sprite companion (`Companions/mochi/idle.png`, …).
    static var companions: URL? { resources?.appendingPathComponent("Companions", isDirectory: true) }
}

/// Environment values for a user-added MCP server live in one Keychain item, "mcp.<server>", as JSON.
nonisolated enum MCPServerSecrets {
    static func key(server: String) -> String { SecretKey.mcpServer(server) }

    static func environment(for server: String, store: any SecretStore) -> [String: String] {
        guard let secret = try? store.get(key(server: server)),
              let dict = try? JSONDecoder().decode([String: String].self, from: Data(secret.reveal().utf8)) else { return [:] }
        return dict
    }

    static func save(_ env: [String: String], for server: String, store: any SecretStore) throws {
        guard !env.isEmpty else { try store.delete(key(server: server)); return }
        let data = try JSONEncoder().encode(env)
        try store.set(key(server: server), Secret(String(decoding: data, as: UTF8.self)))
    }
}
