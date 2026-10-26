# Releasing Sidefolk

The engineering checklist for a public build: what the scripts do, what needs the founder's credentials, and
what to check by hand. Decisions that aren't code (licence, name, website, pricing, accounts) are in
[launch/CHECKLIST.md](launch/CHECKLIST.md). Status as of 2026-10-27, for 0.1.0.

## What the scripts do

- `make app` (`scripts/build-app.sh release`): `swift build -c release --only-use-versions-from-resolved-file`
  for the app and the `sidefolk` helper, assembles `build/Sidefolk.app` (Info.plist from `Resources/Info.plist`,
  version from `Sources/SidefolkCore/Version.swift`, build number from `git rev-list --count HEAD`), compiles the
  string catalog into `.lproj` folders, copies icons, brand art, provider logos, skills, built-in extensions and
  dependency resource bundles, signs inside out with the hardened runtime (helper, then app with
  `Resources/Sidefolk.entitlements`) and verifies with `codesign --verify --deep --strict`. Identity:
  `SIDEFOLK_SIGN_IDENTITY`, else the first "Apple Development" identity, else ad hoc.
- It assembles and signs in `build/.Sidefolk-building-<pid>.app`, then swaps it in with two renames. A running
  `build/Sidefolk.app` keeps working (its program stays mapped; the bundle it was launched from is kept as
  `build/.Sidefolk-replaced-<time>.app` until no process has it open, checked with `lsof`, and a later build
  removes it). A failed build leaves the old app untouched. Relaunch to run the new build: until then the
  running copy reads resources from the new bundle (same names, so this is safe, but strings may be newer).
- `SIDEFOLK_UNIVERSAL=1` adds `--arch arm64 --arch x86_64` (one binary for Apple silicon and Intel). Not yet
  built or tested on an Intel Mac; see "Open decisions".
- `scripts/release.sh`: refuses a dirty tree, an identity that isn't "Developer ID Application", or a missing
  notary profile; runs the full test suite; builds; re-signs inside out with a secure timestamp; checks no
  `get-task-allow` entitlement shipped; notarizes the app (zip via `ditto`), staples and validates it, checks it
  with `spctl --assess --type execute`; builds the DMG (app plus an Applications link), signs it, notarizes,
  staples and validates the DMG, checks it with `spctl`, and writes `build/Sidefolk-<version>.dmg.sha256`.
  A rejected submission prints the notary log. `SIDEFOLK_SKIP_NOTARIZE=1` stops after signing.

## Checklist

**Before the build**
- [ ] `git status` clean on `main`, merged and pushed; `swift build` and `swift test --no-parallel` pass.
- [ ] `Sources/SidefolkCore/Version.swift` says the version being released; `docs/RELEASE-NOTES.md` matches.
- [ ] The build number is `git rev-list --count HEAD`: build from a full clone (a shallow clone gives a small
      number), and never release two builds with the same count. Record it with the tag.
- [ ] `Package.resolved` committed and reviewed (T23): `git diff <last tag> -- Package.resolved`.
- [ ] Translations: `make strings` has been run and `Resources/Localization/Localizable.xcstrings` is
      committed. Info.plist usage descriptions (microphone, speech, Apple Events, local network) are English
      only: add `InfoPlist.strings` per language if the translators can do them in time.

**Signing and notarization (founder's credentials; agents never do this)**
- [ ] Apple Developer Program membership; a "Developer ID Application" certificate in the login keychain
      (`security find-identity -v -p codesigning` lists it).
- [ ] `xcrun notarytool store-credentials sidefolk --apple-id <id> --team-id <TEAMID>` once.
- [ ] `SIDEFOLK_SIGN_IDENTITY="Developer ID Application: … (TEAMID)" SIDEFOLK_NOTARY_PROFILE=sidefolk scripts/release.sh`
- [ ] `codesign -dv --verbose=4 build/Sidefolk.app`: Authority is Developer ID, `flags=0x10000(runtime)`,
      a secure timestamp, TeamIdentifier set; the helper `Contents/Helpers/sidefolk` the same.
- [ ] `codesign -d --entitlements - build/Sidefolk.app`: only `com.apple.security.automation.apple-events`
      and `com.apple.security.device.audio-input`. No `get-task-allow`, no library-validation or JIT exceptions
      (SECURITY T22).
- [ ] `xcrun stapler validate build/Sidefolk.app` and the DMG; `spctl -a -vv -t execute build/Sidefolk.app`
      says "Notarized Developer ID".

**On a clean Mac or a new user account (with the DMG, not the build folder)**
- [ ] Opening the DMG and the app raises no Gatekeeper warning beyond "downloaded from the internet".
- [ ] First launch with no AI: the companion, onboarding, a reminder and a note work without any provider.
- [ ] Prompts appear only when used, each with its text: notifications (onboarding), microphone (first hold of
      the talk key), Automation for Notes and Reminders (first read), local network (a LAN watcher or a model on
      another computer).
- [ ] Login item from /Applications; `sidefolk` installs on PATH from Settings › Agents and answers
      `sidefolk status`.
- [ ] A built-in extension runs in its sandbox (World Clock), and Git shows "can't run" on a Mac without
      developer tools rather than failing silently.
- [ ] Quit and relaunch: reminders and watchers survive; the fallback notifications fire while it is quit.
- [ ] Idle: `top -l 1 -pid $(pgrep -x Sidefolk)` shows ~0 % CPU after the companion settles (see D41 for the
      numbers measured on the dev Mac).

**Publishing**
- [ ] Tag `v<version>` on the released commit; upload the DMG and its `.sha256` (GitHub Releases or the site).
- [ ] Release notes say Apple silicon only unless a universal build was tested on Intel.
- [ ] Keep the DMG and the notarization submission id with the tag.

## Status for 0.1.0

| Item | State |
|---|---|
| Hardened runtime, minimal entitlements, inside-out signing | Done (`build-app.sh`, `release.sh`) |
| Developer ID signing, notarization, stapling (app and DMG) | Script ready; needs the founder's identity and notary profile (none on the build Mac) |
| DMG with an Applications link, signed and notarized | Script ready; same |
| Version and build numbers | Version from `Version.swift` (0.1.0); build from the commit count |
| `make app` over a running app | Fixed: staged build, atomic swap, the replaced bundle kept until unused |
| `get-task-allow` check, notary log on rejection, SHA-256 file | Added to `release.sh` |
| Local network usage description | Added to Info.plist (macOS asks before a LAN watcher or a LAN model) |
| Usage descriptions translated | Not done (English only) |
| Universal binary | Not decided; `SIDEFOLK_UNIVERSAL=1` exists but is untested on Intel |
| Updates | None in 0.1 (D15): no Sparkle, no "Check for updates". People download new versions by hand |
| Crash reporting | None (no telemetry). macOS keeps crash logs in `~/Library/Logs/DiagnosticReports`; ask people to attach the one named Sidefolk with the diagnostics export |
| DMG background, volume icon, licence in the DMG | Not done (plain DMG) |

## Open decisions

- **Intel Macs.** macOS 15 still runs on Intel Macs. A universal build doubles the binary size and needs one test
  on Intel (extensions' interpreters, sandbox-exec and the companion's rendering).
- **Updates.** Sparkle needs an EdDSA key and a hosted appcast; until then the README and the About window
  should say where new versions are announced.
- **Crash reports.** If wanted later: opt-in, local first (show the macOS crash log and let the person send it),
  consistent with "no telemetry".
