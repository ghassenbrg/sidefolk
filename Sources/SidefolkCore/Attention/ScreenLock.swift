import CoreGraphics

/// Whether this login session's screen is locked right now, asked of the window server. The
/// `com.apple.screenIsLocked` / `…Unlocked` distributed notifications carry no proof: any process,
/// sandboxed ones too, can post them to hold or release attention items, so treat them only as a
/// hint to check this.
public enum ScreenLock {
    public static var isLocked: Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (info["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}
