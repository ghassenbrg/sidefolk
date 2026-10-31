import Foundation

public enum SidefolkVersion {
    public static let current = "0.1.0"
    /// This copy's version with its snapshot number when it was published ("0.1.0-snapshot.593", from the
    /// `SidefolkRelease` stamp), else `current`: what an add-on's minimum is compared with (D83).
    public static var running: String {
        (Bundle.main.object(forInfoDictionaryKey: "SidefolkRelease") as? String).flatMap { ReleaseVersion($0)?.description } ?? current
    }
}
