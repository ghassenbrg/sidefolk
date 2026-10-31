import Foundation
import Testing
@testable import SidefolkCore

/// The install sheet's model (D71): the same facts for every source, said calmly only for Sidefolk's own signed
/// extensions; what guards each permission, and what happens after Install, only where the code enforces it.
struct InstallReviewTests {
    let home = FolderAccess.canonical(NSHomeDirectory())!
    /// Miraya's permissions (D69).
    let mirror = ExtensionPermissions(network: true, folders: .read, media: true, screen: true, udp: true,
                                      networkPurpose: "to find TVs on your local network and stream to them")

    private func review(_ id: String, _ p: ExtensionPermissions, _ source: InstallSource, background: Bool = false,
                        tools: [Risk] = [.medium], update: ExtensionUpdateDiff? = nil) -> InstallReview {
        InstallReview(id: id, permissions: p, background: background, toolRisks: tools, update: update, source: source)
    }

    @Test func sidefolksOwnFromTheGalleryIsCalmWithTheSameFacts() {
        let official = review("dev.sidefolk.miraya", mirror, .gallery, background: true)
        let folder = review("com.example.mirror", mirror, .folder, background: true)
        #expect(official.tone == .goodToKnow)
        #expect(folder.tone == .careful)
        #expect(official.cautions == folder.cautions, "the tone changes, never the facts")
        #expect(official.lines == folder.lines && official.next == folder.next)
        #expect(official.cautions.contains("It can record your screen and use the internet, so it could send what's on your screen elsewhere."))
        #expect(official.cautions.contains("It can use the internet while it works in a folder you name, so it could upload what's in that folder."))
    }

    @Test func onlySidefolksSignedCodeEarnsTheCalmTone() {
        // A gallery entry someone else made, a draft (unread code) and any folder, even with Sidefolk's id, stay strong.
        #expect(InstallReview.tone(source: .gallery, id: "com.example.mirror") == .careful)
        #expect(InstallReview.tone(source: .draft, id: "local.mirror") == .careful)
        #expect(InstallReview.tone(source: .folder, id: "dev.sidefolk.miraya") == .careful)
        #expect(InstallReview.tone(source: .gallery, id: "dev.sidefolk.clipboard") == .goodToKnow)
    }

    @Test func aFolderWithTheNetworkAndFilesGetsTheStrongWarning() {
        let r = review("com.example.uploader", ExtensionPermissions(network: true, read: [home + "/Documents"], folders: .write), .folder)
        #expect(r.tone == .careful)
        #expect(r.cautions.contains("It can read ~/Documents and use the internet, so it could upload those files."))
        #expect(r.cautions.contains { $0.contains("upload what's in that folder") })
    }

    @Test func eachGuardIsSaidBesideWhatItGuards() {
        let lines = review("dev.sidefolk.miraya", mirror, .gallery).lines
        let folder = lines.first { $0.kind == .read }
        #expect(folder?.text == "Can read a folder you name, for that request only")
        #expect(folder?.note?.contains("shared with Sidefolk or allow on a card") == true)
        #expect(lines.first { $0.kind == .screen }?.note?.contains("Screen & System Audio Recording") == true)
        #expect(lines.first { $0.kind == .network }?.note == nil, "nothing keeps it to the local network, so nothing is claimed")
        // Without the network, saying so is the guard that matters most beside files.
        let offline = review("dev.sidefolk.images", ExtensionPermissions(folders: .write, media: true), .gallery).lines.map(\.text)
        #expect(offline.last == "Can't use the internet")
        #expect(review("x.y", ExtensionPermissions(power: true), .folder).lines.map(\.text).last == "No access to your files or the internet")
    }

    @Test func whatHappensNextFollowsWhatTheCodeDoes() {
        let miraya = review("dev.sidefolk.miraya", mirror, .gallery, background: true, tools: [.medium, .medium]).next
        #expect(miraya.first == "It runs in a sandbox that allows only what's listed here.")
        #expect(miraya.contains { $0.hasPrefix("It keeps running while it's on") }, "a background program acts without a card")
        #expect(miraya.contains { $0.hasPrefix("Guard asks you before") })
        #expect(miraya.contains { $0.contains("Local Network") })
        #expect(miraya.last == "You can turn it off or remove it any time in Settings › Extensions.")

        let quiet = review("x.y", ExtensionPermissions(media: true), .folder, tools: [.low]).next
        #expect(!quiet.contains { $0.hasPrefix("It keeps running") || $0.contains("Local Network") || $0.hasPrefix("Guard") })
        #expect(quiet.contains("Its tools can't reach the internet or change your files, so Sidefolk's AI may use them without asking."))
        #expect(review("x.y", ExtensionPermissions(media: true), .folder, tools: [.low, .medium]).next.contains { $0.hasPrefix("Guard asks before some") })
        #expect(review("x.y", ExtensionPermissions(), .folder, tools: []).next.count == 2, "no tools, nothing about Guard")
    }

    @Test func anUpdateAskingForMoreStaysProminentEvenWhenSigned() {
        func side(_ version: String, _ p: ExtensionPermissions = ExtensionPermissions(), lines: [String] = [],
                  tools: [String: Risk] = ["make": .low], background: Bool = false) -> ExtensionUpdateDiff.Side {
            .init(version: version, permissions: p, lines: lines, tools: tools, background: background)
        }
        let diff = ExtensionUpdateDiff(from: side("1.0.0"), to: side("1.1.0", ExtensionPermissions(network: true), lines: ["Can use the internet"]))
        let r = review("dev.sidefolk.qr-codes", ExtensionPermissions(network: true), .gallery, update: diff)
        #expect(r.tone == .goodToKnow)
        #expect(r.update?.widens == true && r.update?.added == ["Can use the internet"])
        #expect(r.update?.line == "Updates 1.0.0 to 1.1.0.")
        let again = review("dev.sidefolk.qr-codes", ExtensionPermissions(), .gallery,
                           update: ExtensionUpdateDiff(from: side("1.0.0"), to: side("1.0.0"))).update
        #expect(again?.widens == false && again?.line == "Installs 1.0.0 again.")
        // What the auto-updater holds back for review (D70) is what the sheet shows as asking for more.
        let more = ExtensionUpdateDiff(from: side("1.0.0"), to: side("1.1.0", tools: ["make": .high], background: true))
        let held = review("dev.sidefolk.qr-codes", ExtensionPermissions(), .gallery, update: more).update
        #expect(more.widens && held?.widens == true)
        #expect(held?.added == ["Riskier now: make", "Keeps running in the background now"])
    }
}
