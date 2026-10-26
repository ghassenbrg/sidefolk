import AppKit

AppLanguage.applyLayoutDirection()
#if DEBUG
UISnapshots.runIfRequested()
VoiceDev.runIfRequested()
#endif
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
