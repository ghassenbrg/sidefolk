# Sidefolk: macOS platform review

Environment: macOS 27.0.1 (26A434), Xcode 27.0, Swift 6.4, MacOSX27 SDK, Apple Silicon.
VERIFIED means I compiled it with `swiftc -swift-version 6` (strict concurrency) and, where it says "ran", executed it on this Mac. UNVERIFIED means it comes from headers, docs or experience and was not run.
All probes are in `/private/tmp/claude-501/-Users-ghassenbrg-git-sidefolk/239fdc6a-d479-485e-89ed-4bb71bcd41f6/scratchpad/macos-review/` (`panel_test.swift`, `anim_cpu.swift`, `render_test.swift`, `system_test.swift`, `socket_test.swift`, `main.swift` (spawn), `sqlite_test.swift`, `menu_test.swift`, `child_test.swift`, `bundle/`).

---

## 1. Companion window

```swift
final class CompanionPanel: NSPanel {
    override var canBecomeKey: Bool { false }   // never steals typing
    override var canBecomeMain: Bool { false }
}
let p = CompanionPanel(contentRect: r, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
p.level = .floating                                  // 3; .statusBar is 25 and covers menus, too aggressive
p.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
p.isOpaque = false
p.backgroundColor = .clear
p.hasShadow = false        // the window shadow is recomputed from alpha; draw your own shadow layer with shadowPath
p.hidesOnDeactivate = false
p.canHide = false          // otherwise NSApp.hide(_:) (used to give focus back) hides Pip
p.isReleasedWhenClosed = false
p.animationBehavior = .none
```

- VERIFIED (ran): the defaults are not uniform. A borderless `NSPanel` has `hidesOnDeactivate == true`. Borderless with `.nonactivatingPanel` has `false`. Borderless has `canBecomeKey == false`, while titled with nonactivating has `true`. Set every property explicitly.
- VERIFIED (ran): the collection behavior above (raw value 262481) is accepted without an exception. `.canJoinAllApplications` (macOS 13+) is documented in `NSWindow.h` as "join other apps' sets and full screen spaces… for floating windows and system overlays". Add it to the plan. It cannot be combined with `.primary` or `.auxiliary`.
- UNVERIFIED: with `.canJoinAllSpaces` + `.fullScreenAuxiliary` (+ `.canJoinAllApplications`), an accessory app's panel shows on every Space and over fullscreen apps. Test it by hand while the app is `.regular` too (Home is open). That is the case where floating panels have historically dropped out of fullscreen Spaces.
- Click-through (UNVERIFIED, no synthetic clicks were posted): `ignoresMouseEvents` covers the whole window. Two workable strategies:
  1. Keep the window tight around Pip and never set `ignoresMouseEvents` explicitly. The window server then passes clicks through pixels whose alpha is 0 (the long-standing behavior of the unset tri-state). Soft glows and shadows will catch clicks.
  2. Deterministic: start with `ignoresMouseEvents = true` and flip it from mouse-moved monitors. `NSEvent.h` says only key events need Accessibility, so mouse monitors need no permission:
  ```swift
  // in a @MainActor final class HitGate (typechecks in Swift 6: hit_test.swift)
  NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
      MainActor.assumeIsolated { self?.update(NSEvent.mouseLocation) } }
  NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] e in
      MainActor.assumeIsolated { self?.update(NSEvent.mouseLocation) }; return e }
  func update(_ p: NSPoint) {
      guard panel.frame.insetBy(dx: -4, dy: -4).contains(p) else { panel.ignoresMouseEvents = true; return }
      panel.ignoresMouseEvents = !hitPath.contains(characterView.convert(panel.convertPoint(fromScreen: p), from: nil))
  }
  ```
  Use strategy 2 (typechecks; behavior UNVERIFIED). It costs a rect test per mouse move and nothing while the mouse is still. Global monitors don't fire while the mouse is idle.
- Fullscreen detection (VERIFIED negative case, positive case UNVERIFIED): there is no public "frontmost app is fullscreen" API. Use the heuristic below. Re-check it on `NSWorkspace.didActivateApplicationNotification`, `activeSpaceDidChangeNotification` and `NSApplication.didChangeScreenParametersNotification`, not on a timer. Window bounds, PID and layer don't need Screen Recording permission; window names do. I could not test the no-permission case because this probe inherited a granted TCC context.
  ```swift
  func frontmostCoversADisplay() -> Bool {
      guard let front = NSWorkspace.shared.frontmostApplication,
            let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
      let displays = NSScreen.screens.compactMap { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID).map(CGDisplayBounds) }
      return info.contains { w in
          (w[kCGWindowOwnerPID as String] as? pid_t) == front.processIdentifier && (w[kCGWindowLayer as String] as? Int) == 0 &&
          (w[kCGWindowBounds as String] as! CFDictionary?).flatMap(CGRect.init(dictionaryRepresentation:)).map { r in displays.contains(r) } == true
      }
  }
  ```
  This also catches borderless "maximized" games and slideshows, which is what the product wants.
- Screen sharing (VERIFIED absence): there is no public API. I searched the AppKit, ScreenCaptureKit, CoreGraphics and Foundation headers, and the only "captured" API is the deprecated `CGDisplayIsCaptured`. Don't promise detection. Offer a "Presenting" quiet mode. Fullscreen tuck-away covers most slideshows. `sharingType = .none` would hide Pip from captures, but whether ScreenCaptureKit honors it on 15+ is UNVERIFIED, and it also disables some system services.
- Multi-monitor (VERIFIED ran): key saved positions by `CGDisplayCreateUUIDFromDisplayID` (stable across reboots and re-plugs), not by `CGDirectDisplayID`. `NSScreen.cgDirectDisplayID` is macOS 26+ only. On macOS 15, read `deviceDescription["NSScreenNumber"]`. Store the offset from `visibleFrame.minY` (the "floor") and clamp on `didChangeScreenParametersNotification`. AppKit uses a bottom-left origin and `CGWindowList` uses top-left. Compare in CG space with `CGDisplayBounds`, as above.

## 2. Ask panel (typing without activating)

```swift
final class AskPanel: NSPanel {
    override var canBecomeKey: Bool { true }      // required for borderless
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    var onEscape: (() -> Void)?
}
ask = AskPanel(contentRect: r, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
ask.isFloatingPanel = true; ask.level = .floating; ask.hidesOnDeactivate = false; ask.becomesKeyOnlyIfNeeded = false
ask.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
let host = NSHostingView(rootView: AskView()); host.sizingOptions = [.preferredContentSize]
ask.contentView = host
ask.makeKeyAndOrderFront(nil)          // NOT NSApp.activate()
```

- VERIFIED (ran): after `makeKeyAndOrderFront`, the panel is key and a SwiftUI `TextField` that uses `@FocusState` set in `.onAppear` became first responder (`_SystemTextFieldFieldEditor`). `NSWorkspace.frontmostApplication` stayed `com.google.Chrome`, so the menu bar did not switch. Quirk: `NSApp.isActive` reads `true` while `NSRunningApplication.current.isActive` is `false`, and no `didBecomeActive`/`didResignActive` notifications fire. Never use `NSApp.isActive` to mean "we are frontmost". After `orderOut` the frontmost app was unchanged, so nothing has to be restored.
- VERIFIED (ran): without `NSApp.mainMenu`, ⌘A did nothing in the field (`{0,0}`). With an Edit menu installed it selected all (`{0,11}`). This holds in an accessory app whose menu bar is never visible. Build a main menu with Undo/Cut/Copy/Paste/Select All (and Settings… ⌘,) at launch, or copy and paste will not work anywhere.
- Close on `windowDidResignKey` (Spotlight-like) and on Escape. If the panel content resizes, call `invalidateShadow()`.
- Returning focus when you *did* activate (Home/Settings) is UNVERIFIED; I didn't run it because it would steal the user's focus. Before activating, remember `let prev = NSWorkspace.shared.frontmostApplication` (when it isn't us). On close, call `NSApp.yieldActivation(to: prev)` and then `prev.activate(from: .current, options: [])` (macOS 14 cooperative activation). `NSApp.hide(nil)` is the fallback, which is why `canHide = false` is needed on Pip.

## 3. Core Animation character

- VERIFIED (ran): `anim_cpu`, a 60×60 floating panel, app CPU measured over 4 s:

  | Technique | App CPU |
  |---|---|
  | idle | 0.0% |
  | `CABasicAnimation` + `CAKeyframeAnimation`, `repeatCount = .infinity` | **0.0%** (0.001 s) |
  | `CAShapeLayer` `path` morph, repeat forever | **0.0%** |
  | 60 Hz `Timer` setting a transform | 1.0% |
  | SwiftUI `.repeatForever` scale | **5.5%** |

  Repeating CA animations run in the render server, while SwiftUI `repeatForever` re-evaluates in-process. Keep all idle motion (breathe, blink, zZz) as committed CA animations, and keep SwiftUI out of the companion window.
- WindowServer still composites every frame. For idle loops, set `anim.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 30, preferred: 30)` (macOS 12+, VERIFIED in header). Pause with `layer.speed = 0` (keeping `timeOffset`) when asleep, when the window is occluded (`didChangeOcclusionStateNotification`), on `screensDidSleep`, or when Reduce Motion is on.
- Path morphing (UNVERIFIED rule, VERIFIED working): both paths need the same number and order of elements (move/curve/close). Build every pose's part through one function that always emits, say, four cubics per eye. `path` has no implicit animation (header), so add a `CABasicAnimation(keyPath: "path")` explicitly. Set `fillMode = .forwards` plus the model value, not `isRemovedOnCompletion = false` alone.
- Budget: well under 50 layers, no `mask` on animated layers (offscreen pass), `shadowPath` always set, `shouldRasterize = false` on anything animated. The app should do work only at state transitions, under 1 ms each.
- Offscreen rendering for `sidefolk-render` (VERIFIED ran, pixel probes):
  - `CALayer.render(in:)` renders **shadows, masks, opacity and affine transforms**, but **not 3D transforms**: an 81° Y rotation drew flat. It renders **model values only**, so animations are ignored. It is fine for static pose sheets.
  - `CARenderer(mtlTexture:options:)` renders all of the above **including 3D** and **samples animations at any time**: with `anim.beginTime = 1.0` it showed the model value at t=0, 150 at t=1.5 and 180 at t=3. Use it for animation filmstrips. Two gotchas I hit: set `renderer.layer = root` **before** `CATransaction.commit(); CATransaction.flush()`, otherwise output is blank. Also, `beginTime = 0` means "now" (CACurrentMediaTime), so set explicit begin times.
  ```swift
  let q = dev.makeCommandQueue()!
  let r = CARenderer(mtlTexture: tex, options: [kCARendererColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, kCARendererMetalCommandQueue: q])
  CATransaction.begin(); CATransaction.setDisableActions(true); r.layer = root; r.bounds = root.bounds; CATransaction.commit(); CATransaction.flush()
  r.beginFrame(atTime: t, timeStamp: nil); r.addUpdate(r.bounds); r.render(); r.endFrame()
  let cb = q.makeCommandBuffer()!; cb.commit(); cb.waitUntilCompleted()   // then tex.getBytes (BGRA, row 0 = bottom)
  ```
  Texture storage must be `.shared` (`.managed` is deprecated in the macOS 27 SDK). The Swift name is `addUpdate(_:)`, not `addUpdateRect`. Use sRGB colors for exact pixel values.

## 4. Notifications from a script-assembled .app

- VERIFIED (ran): calling `UNUserNotificationCenter.current()` from an unbundled binary (`swift run`) **crashes** with `NSInternalInconsistencyException: bundleProxyForCurrentProcess is nil`. Guard every use with `Bundle.main.bundleIdentifier != nil`.
- VERIFIED (ran): inside an ad-hoc-signed bundle with hardened runtime, the center works and `notificationSettings().authorizationStatus == .notDetermined`. I didn't call `requestAuthorization`, to avoid a prompt. UNVERIFIED: whether the prompt appears for ad-hoc builds. In my experience it does, and authorization is keyed to the bundle ID.
- VERIFIED compile, Swift 6 delegate:
  ```swift
  final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
      nonisolated func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound, .list] }
      nonisolated func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse) async {
          let (action, info) = (r.actionIdentifier, r.notification.request.content.userInfo["reminder"] as? String)
          await MainActor.run { AppRouter.shared.handle(action, reminderID: info) }
      }
  }
  // categories: UNNotificationCategory(identifier: "reminder", actions: [done, snooze10, open(.foreground)], intentIdentifiers: [], options: [.customDismissAction])
  ```
  Per the header, set the delegate in `applicationWillFinishLaunching`, before launch returns, or the response that launched the app is lost.
- `.timeSensitive` needs the `com.apple.developer.usernotifications.time-sensitive` entitlement, which a Developer ID build without a provisioning profile can't get (UNVERIFIED). "critical" should map to `.active` + sound, and Focus may hold it. Pending notification limits on macOS are UNVERIFIED (iOS caps at 64), so schedule only the next N fallback reminders.

## 5. Login item

- VERIFIED (ran): `SMAppService.mainApp.status` returns `.notFound` (3) for a never-registered ad-hoc app, whether launched directly or through LaunchServices. Treat `.notFound` as "off".
- UNVERIFIED (not run, because `register()` posts a system "Login Item Added" notice): `register()` works for ad-hoc-signed apps in any folder. Background Task Management records the bundle at its current path, and the ad-hoc designated requirement is `cdhash H"…"` (VERIFIED), which changes on every build. Expect stale or duplicate entries during development. Offer the toggle only when `Bundle.main.bundleURL` is under `/Applications` (or show a warning). Call `register()` only from the user's toggle. On `.requiresApproval`, call `SMAppService.openSystemSettingsLoginItems()`.

## 6. Global hotkey

- VERIFIED (ran): Carbon `RegisterEventHotKey` needs no Accessibility permission and compiles cleanly in Swift 6 (C callback with no captures + `MainActor.assumeIsolated`; see `system_test.swift`). **⌥Space registers fine** for a non-sandboxed app on macOS 27; KeyboardShortcuts' source documents that the Option-only block was limited to sandboxed apps on 15.0–15.1. Registering the same combo twice in one process returns `-9878 eventHotKeyExistsErr`. **Two processes registering the same combo both get `noErr`** (VERIFIED with two concurrent processes), so you can't detect that ChatGPT, Raycast or another app already owns ⌥Space. Show the shortcut in onboarding and make it easy to change.
- VERIFIED (built 3.1.0 from the local SPM cache): **sindresorhus/KeyboardShortcuts 3.1.0** builds with no warnings on Swift 6.4. It uses `swift-tools-version:6.2`, `.defaultIsolation(MainActor.self)` and Carbon underneath. **Gotcha:** it ships a resource bundle (`KeyboardShortcuts_KeyboardShortcuts.bundle`, localized strings via `Bundle.module`). In release builds the generated accessor searches `Bundle.main.resourceURL`, the framework bundle and `Bundle.main.bundleURL`, and otherwise calls **`fatalError`**. The recorder in Settings will crash unless `build-app.sh` copies that bundle into `Sidefolk.app/Contents/Resources/`, which signs fine (§7). Either amend the "no SPM resource bundles" rule to "copy them into Contents/Resources", or use the ~60-line Carbon wrapper plus your own recorder and drop the dependency.

## 7. Bundling, signing, notarization

`Contents/Info.plist` (VERIFIED with `plutil -lint` and by running the bundle):
`CFBundleIdentifier`, `CFBundleExecutable` (= `Sidefolk`), `CFBundleName`, `CFBundleDisplayName`, `CFBundlePackageType`=APPL, `CFBundleShortVersionString`, `CFBundleVersion`, `CFBundleInfoDictionaryVersion`=6.0, `CFBundleIconFile`=AppIcon, `LSMinimumSystemVersion`=15.0, `LSUIElement`=true, `NSHighResolutionCapable`=true, `LSApplicationCategoryType`=public.app-category.productivity, `NSPrincipalClass`=NSApplication (harmless; `main.swift` creates the app). Add `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` now: a missing usage string kills the process the moment the mic is touched.

Icon (VERIFIED): `sips -z N N base.png --out icon.iconset/icon_NxN.png` (and the @2x sizes for 16/32/128/256/512), then `iconutil -c icns icon.iconset -o Contents/Resources/AppIcon.icns`. UNVERIFIED: macOS 26+ draws non-conforming legacy icons inside a gray squircle. Draw a full-bleed squircle, or compile an Icon Composer `.icon` with `xcrun actool` (flags not verified).

Signing (VERIFIED ad-hoc, VERIFIED failure modes):
```sh
# inside-out; never --deep for signing
codesign --force --options runtime --timestamp --sign "$ID" --identifier app.sidefolk.cli Sidefolk.app/Contents/Helpers/sidefolk
codesign --force --options runtime --timestamp --sign "$ID" [--entitlements Sidefolk.entitlements] Sidefolk.app
codesign --verify --strict --deep --verbose=2 Sidefolk.app
# ad-hoc dev: ID="-" and drop --timestamp
```
- If the app is signed before the helper: `nested code is modified or invalid` (VERIFIED).
- A resource bundle at the `.app` root fails with `unsealed contents present in the bundle root` (VERIFIED). Under `Contents/Resources` it verifies (VERIFIED).
- Ad-hoc + `--options runtime` runs fine (`flags=0x10002(adhoc,runtime)`, VERIFIED).
- Entitlements: **none** for the base app. Later: `com.apple.security.device.audio-input` for the mic under hardened runtime, and `com.apple.security.automation.apple-events` + `NSAppleEventsUsageDescription` if "take you to that exact session" scripts Terminal or iTerm. Don't add any `com.apple.security.cs.*` entitlement. Child processes (claude, python) carry their own signatures.
- Dev stability: the ad-hoc designated requirement is the cdhash (VERIFIED), so Keychain ACLs and any TCC grant (mic, later) break on every rebuild (UNVERIFIED consequence). An "Apple Development" identity exists in the login keychain; signing dev builds with it gives a stable requirement.

Release (flags VERIFIED in `--help`, not run):
```sh
ditto -c -k --keepParent Sidefolk.app Sidefolk.zip
xcrun notarytool submit Sidefolk.zip --keychain-profile "$SIDEFOLK_NOTARY_PROFILE" --wait && xcrun stapler staple Sidefolk.app
mkdir dmg && cp -R Sidefolk.app dmg/ && ln -s /Applications dmg/Applications
hdiutil create -volname Sidefolk -srcfolder dmg -ov -format UDZO -fs APFS Sidefolk.dmg     # VERIFIED
codesign --force --timestamp --sign "$ID" Sidefolk.dmg
xcrun notarytool submit Sidefolk.dmg --keychain-profile "$SIDEFOLK_NOTARY_PROFILE" --wait && xcrun stapler staple Sidefolk.dmg
spctl -a -vvv -t install Sidefolk.dmg; spctl -a -vvv Sidefolk.app
```
(One-time setup: `xcrun notarytool store-credentials sidefolk-notary --apple-id … --team-id …`.)

## 8. Accessibility

VERIFIED compile:
```swift
final class CharacterView: NSView {
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { "\(name), your Sidefolk companion" }
    override func accessibilityValue() -> Any? { presenter.stateWord }   // from the state vocabulary
    override func accessibilityPerformPress() -> Bool { openAsk(); return true }
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? { [.init(name: "Open Home") { openHome(); return true }] }
}
NSAccessibility.post(element: view, notification: .announcementRequested,
                     userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])  // bubbles
```
Reduce Motion: `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`. Observe `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` on `NSWorkspace.shared.notificationCenter` (VERIFIED header, compile and read). Swap loops for static poses plus cross-fades. Because the companion can never become key, VoiceOver users also need the menu bar item and hotkey paths. UNVERIFIED: how VoiceOver navigates to a non-key floating panel.

## 9. Idle, sleep, lock, clock

- VERIFIED (ran): `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)` and IOKit `IOHIDSystem`/`HIDIdleTime`/1e9 agree (101.22 vs 101.23 s). Neither prompted, but this process inherited its parent's TCC context.
- VERIFIED compile (firing not observed): `NSWorkspace` `willSleep`, `didWake`, `screensDidSleep`, `screensDidWake`, `sessionDidResignActive`/`sessionDidBecomeActive` (fast user switching) on `NSWorkspace.shared.notificationCenter`. On the default center: `.NSSystemClockDidChange`, `.NSSystemTimeZoneDidChange`, `.NSCalendarDayChanged`. On `DistributedNotificationCenter`: `com.apple.screenIsLocked`/`Unlocked` (undocumented but long-stable).
- Swift 6 pattern: `addObserver(forName:object:queue: .main) { n in let s = n.name; MainActor.assumeIsolated { self?.handle(s) } }`. Extract Sendable values before hopping; capturing a CALayer in a `@Sendable` closure is a hard error (VERIFIED).
- Reminder timer: one `Task.sleep(until:)` (ContinuousClock keeps counting while asleep), computed from `Date`, re-armed on `didWake`, clock change, time zone change and day change. Use a small tolerance so the system can coalesce wakeups.

## 10. Unix socket

VERIFIED (ran, `socket_test.swift`): POSIX + `DispatchSource` server; `getpeereid` returned uid 501; `getsockopt(SOL_LOCAL, LOCAL_PEERPID)` returned the client PID; the socket file was 0600 and the directory 0700; an `NWConnection(to: .unix(path:))` client interoperates.
- **`sun_path` is 104 bytes** (VERIFIED). The production path for this user is 72 bytes, fine. **The scratch path on this machine was 142 bytes and failed**, as will most `$TMPDIR`-based `SIDEFOLK_HOME` test folders. Throw a clear `pathTooLong` error, and give tests short roots (e.g. `/tmp/sf-<6 chars>`).
- `NWListener` with `requiredLocalEndpoint = .unix(path:)` works, but it created the socket file **0755** (umask) and exposes no fd or peer credentials, so there is no uid check. Use POSIX.
- Set `SO_NOSIGPIPE` on accepted fds, use non-blocking fds and a per-client line cap. Prefer `chmod(path, 0o600)` right after `bind` (the directory is 0700) over process-wide `umask` juggling. `unlink` a stale socket at start, but only after probing that no live instance answers (single-instance guard).
- Consider `LOCAL_PEERTOKEN` (audit token) plus `SecCodeCopyGuestWithAttributes` to require that the peer is the signed `sidefolk` helper (UNVERIFIED).

## 11. Child processes

VERIFIED (ran, `main.swift`):
- `posix_spawn` with `POSIX_SPAWN_SETPGROUP` (pgid 0), `POSIX_SPAWN_CLOEXEC_DEFAULT` (only the dup2'd fds are inherited), `SETSIGDEF` and `SETSIGMASK`, an explicit env (`PATH`, `HOME`, `TMPDIR`, `LANG`) and `addchdir_np`. `kill(-pgid, SIGTERM)` removed all 3 group members (`sh` + 2 `sleep`). Foundation `Process` can't set a process group, so `terminate()` leaves grandchildren (`node` under `claude`). Escalate to SIGKILL after a grace period. A child that calls `setsid` itself escapes the group.
- `sandbox-exec` still exists and works on macOS 27, although `man sandbox-exec` says **DEPRECATED**. `(deny file-write*)(allow file-write* (subpath DATA))` blocked a write outside and allowed one inside. `(deny network*)` blocked a TCP connect to a live local listener, which an unsandboxed curl reached. **Gotcha (VERIFIED):** `URL.resolvingSymlinksInPath()` turns `/private/tmp/...` into `/tmp/...`, the profile then silently matches nothing, and even in-dir writes failed. Canonicalize with `realpath(3)`. Note the risk in DECISIONS: there is no supported replacement.
- `addchdir_np` is deprecated in the macOS 26 SDK. Wrap the replacement `posix_spawn_file_actions_addchdir` in `#available(macOS 26, *)`. At a 15.0 deployment target there is no warning (VERIFIED).
- Line reading: `for try await line in handle.bytes.lines` (VERIFIED). If a grandchild keeps stdout open, EOF never arrives, so tie stream lifetime to the group kill.
- **SIGPIPE (VERIFIED):** writing to a dead child's stdin killed the probe (exit 141). Call `fcntl(fd, F_SETNOSIGPIPE, 1)` on every pipe you write to, or `signal(SIGPIPE, SIG_IGN)` at startup.

## 12. GRDB / SQLite

- VERIFIED (ran): the system SQLite on macOS 27 is **3.54.0** with `ENABLE_FTS5=1`, FTS5 external-content plus triggers, `bm25()`, `unicode61 remove_diacritics 2` ("resume" matched "résumé"), the `trigram` tokenizer and built-in JSON. macOS 15's bundled version is UNVERIFIED, but FTS5 has shipped in macOS SQLite for many releases. Avoid features newer than about 3.43 or check them at runtime.
- GRDB 7 itself is UNVERIFIED (the SPM cache for it is empty, and I did not fetch). As I recall, GRDB 7 targets the Swift 6 language mode, `DatabasePool` is `Sendable`, and its SPM manifest defines `SQLITE_ENABLE_FTS5`. Check this on first `swift build`.
- **Pitfall (VERIFIED with a stand-in module):** under `-default-isolation MainActor` + `InferIsolatedConformances` (how the app target is planned, and how KeyboardShortcuts builds), a record `struct Note: FetchableRecord` gets a *main-actor-isolated conformance*, and `pool.read { fetchAll(Note.self, $0) }` fails: "main actor-isolated conformance … cannot be used in nonisolated context". Keep every record in `SidefolkCore` with the default nonisolated isolation, or mark records `nonisolated struct`. Use structs, not GRDB's `Record` class.

## 13. Other pitfalls in the plan

1. **Bubbles as child panels** (VERIFIED): children move with the parent and hide or show with `orderOut`/`orderFront`, but they **do not inherit `collectionBehavior`** (the child read 64). Give bubbles the same behavior and level explicitly.
2. **Activation policy switching** (UNVERIFIED, not run because it steals focus): call `setActivationPolicy(.regular)`, then on the next run-loop turn `NSApp.activate()` and `makeKeyAndOrderFront`. The menu bar sometimes stays stale if you activate in the same turn. On the last close, return to `.accessory` and hand focus back (§2). Cooperative activation (macOS 14+) honors activation that follows the user's click, hotkey or menu choice. Don't activate from timers.
3. **Settings:** SwiftUI's `Settings` scene, `SettingsLink` and `openSettings` need the SwiftUI `App` lifecycle. With an AppKit delegate, host `NSHostingController` in your own `NSWindow` (`isReleasedWhenClosed = false`, a strong reference), and wire "Settings… ⌘," in the main menu yourself. Likewise use `NSStatusItem` + `NSMenu` (template image), not `MenuBarExtra`.
4. **The MCP helper path is written into other tools' configs.** If the app runs translocated (`/AppTranslocation/` in the path) or is moved later, Claude Code's config points at a dead path. Refuse to connect while translocated, and write a stable symlink (`~/Library/Application Support/Sidefolk/bin/sidefolk`) refreshed at each launch.
5. **Single instance:** dev and release builds share the socket and DB unless `SIDEFOLK_HOME` differs. Use different bundle IDs for dev (`app.sidefolk.dev`) so notification authorization and login items don't collide.
6. **Deployment target:** set `platforms: [.macOS(.v15)]`. Swift 6.4 features whose runtime ships only with macOS 26+ will then fail availability checks instead of crashing on 15. Run the app on macOS 15 before release; nothing tonight ran there.
7. **Strict concurrency + AppKit:** Timer, NotificationCenter and NSEvent monitor closures are `@Sendable`. Route them to MainActor methods (VERIFIED patterns above), never capture layers or views directly.

## 14. Apple Events: Notes and Reminders (D38)

VERIFIED (ran, no Apple Event sent):
- `osascript -l JavaScript -` reads the script from stdin and prints the string the `run()` handler
  returns. Its JavaScriptCore has `Proxy`, and `JSON.stringify` writes dates as ISO 8601 with
  milliseconds. The tests run the real programs this way against a stand-in object model.
- Property names come from the apps' own dictionaries, read from their bundles:
  `/System/Applications/Notes.app/Contents/Resources/Notes.sdef` (account, folder with `container`,
  note with `body` HTML, `plaintext`, `creation date`, `modification date`, `password protected`;
  attachment with `content identifier`, the `cid:` its image has in the note's HTML) and
  `Reminders.app/…/Reminders.sdef` (list, reminder with `completed`, `due date`, `allday due date`,
  `priority`, `flagged`, `body`). JXA spells them camelCase (`creationDate`, `contentIdentifier`).
- Notes' word for its Recently Deleted folder is in
  `/System/Library/PrivateFrameworks/NotesShared.framework/Resources/Localizable.loctable` under the key
  "Recently Deleted" (de "Zuletzt gelöscht", fr "Suppr. récentes", ja "最近削除した項目" …).

UNVERIFIED (deliberately not run against the real apps: no Automation prompt, nobody's notes read):
- Whether `folders` of an account lists nested folders too, and whether `notes` of a folder includes
  its subfolders' notes. The index script records every folder that lists a folder and the code keeps
  the deepest, so either answer gives the same tree (tested with the stand-in both ways).
- That scripting shows Recently Deleted as a folder and that `delete` moves a note there. Removing is
  refused in an account where that folder isn't found, and a note is reported as moved only when it is
  seen there afterwards.
- That macOS attributes the child `osascript`'s Apple Events to Sidefolk (the responsible process), so
  the prompt names Sidefolk and the switch sits under Sidefolk in Privacy & Security › Automation.
- That the hardened runtime needs `com.apple.security.automation.apple-events` for events sent by a child
  (it does for the app's own); the entitlement is in `Resources/Sidefolk.entitlements` either way.

