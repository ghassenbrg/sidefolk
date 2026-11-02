import AppKit
import Collaboration

/// The Mac account's picture, read once from the local directory; nil when it has none. An extension can place it on its page (D100)
/// and never reads it: only Sidefolk draws it.
enum AccountPicture {
    @MainActor static let current: NSImage? = {
        guard let identity = CBIdentity(name: NSUserName(), authority: CBIdentityAuthority.local()) as? CBUserIdentity else { return nil }
        return identity.image
    }()
}
