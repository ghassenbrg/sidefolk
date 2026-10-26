import Foundation
import Testing
@testable import SidefolkCore

/// The built-ins' words come from the string catalog (other languages) and their manifests (the model,
/// hand-installed copies). In English they must be the same words, or a manifest edit would show in one
/// place and not the other.
struct BuiltInExtensionWordsTests {
    @Test func everyBuiltInWordMatchesItsManifestInEnglish() throws {
        for folder in ["git", "world-clock", "system-vitals", "weather"] {
            let url = ExtFixtures.repoRoot.appendingPathComponent("extensions/\(folder)/\(ExtensionManifest.fileName)")
            let manifest = try ExtensionManifest.decode(try Data(contentsOf: url))
            #expect(BuiltInExtensionWords.name(manifest.id) == manifest.name, "\(folder)")
            #expect(BuiltInExtensionWords.description(manifest.id) == manifest.description, "\(folder)")
            for (tool, meta) in manifest.tools {
                #expect(BuiltInExtensionWords.tool(manifest.id, tool) == meta.title, "\(folder) \(tool)")
            }
            for (watcher, meta) in manifest.watchers {
                #expect(BuiltInExtensionWords.watcher(manifest.id, watcher) == meta.title, "\(folder) \(watcher)")
            }
        }
    }
}
