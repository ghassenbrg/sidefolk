import Foundation
import Testing
@testable import SidefolkCore

/// An extension's result card offering one of its own pages as Open in Home (D221, T54): an offer the person's click takes up, never a move.
struct CardPageTests {
    @Test func aCardOffersOnlyAPageItsOwnManifestDeclares() throws {
        let manifest = try ExtensionManifest.decode(Data(#"{"id":"com.example.a","name":"A","version":"1.0.0","run":{"command":"python3","args":["s.py"]},"tools":{},"pages":{"flows":{"title":"Flows"}}}"#.utf8))
        let offer = ExtensionToolAsks(["card_page": ["page": "flows", "state": ["flow": "f1"], "push": true]], manifest: manifest)
        #expect(offer?.cardPage == PageMove(page: "flows", state: ["flow": "f1"]), "the state kept, and nothing about Back: the click opens it")
        #expect(offer?.openPage == nil, "an offer is not a move")
        #expect(ExtensionToolAsks(["card_page": "flows"], manifest: manifest)?.cardPage == PageMove(page: "flows"))
        #expect(ExtensionToolAsks(["card_page": ["page": "nope"]], manifest: manifest) == nil, "a page it doesn't declare leaves nothing")
        #expect(ExtensionToolAsks(["card_page": ["page": "com.example.b/flows"], "row": "x"], manifest: manifest)?.cardPage == nil, "nor another extension's")
        let huge: JSONValue = ["page": "flows", "state": ["words": .string(String(repeating: "a", count: PageState.maxBytes))]]
        #expect(ExtensionToolAsks(["card_page": huge], manifest: manifest)?.cardPage == PageMove(page: "flows"), "too much state is left out, as open_page's is")
    }

    @Test func aCardWrittenBeforeOffersNothing() throws {
        let card = try JSONDecoder().decode(ResultCard.self, from: Data(#"{"kind":"extensionResult","title":"Ran","refId":"com.example.a"}"#.utf8))
        #expect(card.page == nil && card.pageState == nil)
        var offering = card
        offering.page = "flows"
        offering.pageState = ["flow": "f1"]
        let again = try JSONDecoder().decode(ResultCard.self, from: JSONEncoder().encode(offering))
        #expect(again.page == "flows" && again.pageState == ["flow": "f1"], "kept in History as written")
    }

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func theCardCarriesTheOfferAndTheClickIsCheckedAgain() async throws {
        let h = try HostEnv()
        let info = try await SurfaceReviewTests().install(h)
        let asks: JSONValue = ["asks": ["card_page": ["page": "home", "state": ["run": "r1"]]]]
        let out = await h.env.executor.execute(name: "ext.review.start", input: asks, caller: .agent(runId: "r"))
        guard case .ok(let result) = out.status else { Issue.record("the call failed: \(out.status)"); return }
        #expect(result.card?.page == "home" && result.card?.pageState == ["run": "r1"])
        #expect(await h.host.takePageMoves("\(info.id)/home").isEmpty, "nothing moves until the person clicks, an agent's call or not")

        #expect(await h.host.openOffered(extensionId: info.id, page: "home", state: ["run": "r1"]) == "\(info.id)/home")
        #expect(await h.host.takePageMoves("\(info.id)/home") == [PageGo(set: ["run": "r1"])], "the click takes the state to the page")
        #expect(await h.host.openOffered(extensionId: info.id, page: "gone", state: nil) == nil, "a page the manifest no longer declares")
        #expect(await h.host.openOffered(extensionId: "dev.test.elsewhere", page: "home", state: nil) == nil, "an extension that isn't installed")
        try await h.host.setEnabled(false, id: info.id)
        #expect(await h.host.openOffered(extensionId: info.id, page: "home", state: ["run": "r1"]) == nil, "one turned off since")
        #expect(await h.host.takePageMoves("\(info.id)/home").isEmpty, "and nothing was queued for it")
    }
}
