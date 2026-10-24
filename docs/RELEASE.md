# Releasing Sidefolk

What is ready, and the steps that need your accounts and keys. Nothing here has been run
yet: signing, notarizing and auto-update all need credentials only you should hold.

## Ready in the repo

- `npm run build` makes `src-tauri/target/release/bundle/macos/Sidefolk.app` (about 6.5 MB).
- `scripts/release.sh` runs every check and builds a signed, notarized app and DMG once the
  keys below are set (it refuses to build an unsigned release unless you pass `--unsigned`).
- A Dock app with menus; `Info.plist` keeps `LSUIElement` so "Hide from Dock" never flashes an
  icon at launch (the app sets its own activation policy right after).
- Setup guide on first launch, local crash and error logs (`<data dir>/logs`), Settings → About
  and help → Copy report for bug reports, and docs/GUIDE.md for people trying it.
- The data directory is `~/Library/Application Support/dev.sidefolk.companion`.
- CPU, 24 October 2026 (release build, running app plus its three web view processes, 60 s):
  about 1.3% on average.

## 1. Sign and notarize (Developer ID)

Needs an Apple Developer account and a **Developer ID Application** certificate in your
login keychain.

```sh
security find-identity -v -p codesigning     # copy the "Developer ID Application: …" name
export APPLE_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
# Notarization with an app-specific password (appleid.apple.com → Sign-In and Security):
export APPLE_ID="you@example.com"
export APPLE_PASSWORD="xxxx-xxxx-xxxx-xxxx"
export APPLE_TEAM_ID="TEAMID"
npx tauri build --bundles app,dmg
```

Tauri signs with the hardened runtime and submits to notarization when these variables are
set. Check the result with `spctl -a -vv src-tauri/target/release/bundle/macos/Sidefolk.app`.

`macOSPrivateApi` (needed for the transparent overlay) rules out the Mac App Store; Developer
ID distribution is the route.

## 2. Auto-update

Uses `tauri-plugin-updater`, which is not added yet because it refuses to start without a
public key.

1. `npx tauri signer generate -w ~/.tauri/sidefolk.key` and keep the private key and
   its password out of the repo (a password manager or CI secret).
2. `cd src-tauri && cargo add tauri-plugin-updater` and `npm i @tauri-apps/plugin-updater`.
3. In `tauri.conf.json`: `"bundle": { "createUpdaterArtifacts": true }` and
   `"plugins": { "updater": { "pubkey": "<contents of sidefolk.key.pub>", "endpoints": ["https://github.com/<you>/sidefolk/releases/latest/download/latest.json"] } }`.
4. Register the plugin in `main.rs` and check once a day from the tray ("Check for updates…"),
   installing only after the user agrees.
5. Build with `TAURI_SIGNING_PRIVATE_KEY` and `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` set, upload
   the `.app.tar.gz`, its `.sig` and a `latest.json` to the release.

## 3. Before each release

- `scripts/release.sh` (or by hand: `npm run typecheck && npm test && (cd src-tauri && cargo test)`
  and, with `npm run web` running, `npm run check:webkit`).
- `npm run sprites` (and `npm run sprites -- spark`) if the sheets in `art/` changed.
- `npm run measure` with the screen awake and unlocked and no other Sidefolk running.
- Try a fresh data directory (`open` would drop the variable, so run the binary):
  `SIDEFOLK_DATA_DIR=$(mktemp -d) Sidefolk.app/Contents/MacOS/sidefolk` shows the setup guide.
- Hand checks in docs/REMINDER-CHECKS.md and the "done when" checks in docs/PLAN-V2.md section 6.

## Windows

Not started. The overlay (`panel.rs`), idle time and cursor (`overlay.rs`) and the hold policy's
frontmost-app check are macOS-only. Each has a `cfg(not(target_os = "macos"))` branch, but
none has been built or run on Windows yet.
