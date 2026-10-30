import Foundation
import Testing
@testable import SidefolkCore

/// The built-ins' words come from the string catalog (other languages) and their manifests (the model,
/// hand-installed copies). In English they must be the same words, or a manifest edit would show in one
/// place and not the other.
struct BuiltInExtensionWordsTests {
    @Test func everyBuiltInWordMatchesItsManifestInEnglish() throws {
        // The gallery's too: Sidefolk's own add-ons are translated in the app (D55), when a checkout of them is here.
        #expect(ExtFixtures.builtInFolders.count == 4)
        for folder in ExtFixtures.builtInFolders + ExtFixtures.addonFolders {
            let url = ExtFixtures.source(folder).appendingPathComponent(ExtensionManifest.fileName)
            let manifest = try ExtensionManifest.decode(try Data(contentsOf: url))
            #expect(BuiltInExtensionWords.name(manifest.id) == manifest.name, "\(folder)")
            #expect(BuiltInExtensionWords.description(manifest.id) == manifest.description, "\(folder)")
            // Every built-in has a line that fits under its name in Settings.
            #expect(BuiltInExtensionWords.tagline(manifest.id) == manifest.tagline, "\(folder)")
            #expect((1...60).contains(manifest.tagline?.count ?? 0), "\(folder)")
            for (tool, meta) in manifest.tools {
                #expect(BuiltInExtensionWords.tool(manifest.id, tool) == meta.title, "\(folder) \(tool)")
            }
            for (watcher, meta) in manifest.watchers {
                #expect(BuiltInExtensionWords.watcher(manifest.id, watcher) == meta.title, "\(folder) \(watcher)")
            }
            for (page, meta) in manifest.pages {
                #expect(BuiltInExtensionWords.page(manifest.id, page) == meta.title, "\(folder) \(page)")
            }
        }
    }
}
