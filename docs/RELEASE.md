# Releasing Sidefolk

What is ready, and the steps that need your accounts and keys. Nothing here has been run
yet: signing, notarizing and auto-update all need credentials only you should hold.

## Ready in the repo

- `npm run build` makes `src-tauri/target/release/bundle/macos/Sidefolk.app` (about 4 MB).
- `src-tauri/Info.plist` sets `LSUIElement`, so there is no Dock icon, even at launch.
- Settings window, first-run card, local crash and error logs (`<data dir>/logs`).
- The data directory is `~/Library/Application Support/dev.sidefolk.companion`.

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

- `npm run typecheck && npm test && (cd src-tauri && cargo test)`
- `npm run model` if `art/blender/build_hero.py` changed.
- `npm run measure` with the screen awake and unlocked; record the result in docs/PHASE1.md.
- Try a fresh data directory (`open` would drop the variable, so run the binary):
  `SIDEFOLK_DATA_DIR=$(mktemp -d) Sidefolk.app/Contents/MacOS/sidefolk` shows the first-run card.

## Windows

Not started. The overlay (`panel.rs`), idle time and cursor (`overlay.rs`) and the hold policy's
frontmost-app check are macOS-only. Each has a `cfg(not(target_os = "macos"))` branch, but
none has been built or run on Windows yet.
