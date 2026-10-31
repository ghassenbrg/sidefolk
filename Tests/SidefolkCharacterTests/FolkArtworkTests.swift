import AppKit
import Testing
@testable import SidefolkCharacter

@MainActor @Suite struct FolkArtworkTests {
    @Test(arguments: Folk.allCases)
    func eachHelperUsesItsBundledRedesign(_ folk: Folk) {
        let image = Art.image("folks/\(folk.rawValue)")
        #expect(image != nil, "Missing artwork for \(folk.rawValue)")
        let rig = FolkRig(folk)
        #expect(rig.body.sublayers?.count == 1)
        #expect(rig.body.sublayers?.first?.contents != nil)
        #expect(rig.body.sublayers?.first?.frame == CGRect(origin: .zero, size: FolkCanvas.size))
    }
}
