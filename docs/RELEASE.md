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
  `SIDEFOLK_RELEASE_LABEL` names the image `Sidefolk-<version>-<label>.dmg`; `SIDEFOLK_NOTARY_KEYCHAIN` points
  notarytool at a keychain other than the login one (CI).
- `scripts/package.sh [label]`: the disk image alone (app plus an Applications link) and its `.sha256`, from
  `build/Sidefolk.app` as it is; nothing more is signed or notarized. For an install on your own Mac, or an
  unsigned snapshot.

## GitHub Actions

Two workflows in `.github/workflows/`, both on a macOS runner.

- **CI** (`ci.yml`) runs on every push to `main` and every pull request into `main` (and `master`, if the
  branch is ever renamed), nothing else: `swift build`, the full serial test suite, a translations report (a
  warning, not a failure, when a language misses strings) and `scripts/build-app.sh release`, ad hoc signed.
- **Release** (`release.yml`) makes either:
  - a **production** release: the version in `Version.swift`, tagged `v<version>`, signed with Developer ID,
    notarized, with `docs/RELEASE-NOTES.md` as its notes. Push the tag (`git tag v0.1.0 && git push origin
    v0.1.0`), or run the workflow with *production*. It refuses without the signing secrets, when a pushed tag
    doesn't match `Version.swift`, and when `v<version>` already marks another commit (raise the version);
  - a **snapshot**: a prerelease of the chosen branch's commit, tagged `v<version>-snapshot.<build>`, signed
    and notarized when the secrets exist and ad hoc signed otherwise (its notes then say how to open it). A
    snapshot of the same commit replaces the earlier one, and only the latest ten are kept.

  Run it from **Actions › Release › Run workflow**: pick the branch, the channel (snapshot by default) and,
  if wanted, *universal* (Apple silicon and Intel). The image and its checksum are attached to the release
  and kept as the run's artifact. `scripts/ci/release-plan.sh` decides channel, tag and file name and can be
  run locally first (`CHANNEL=production SIGNING=yes scripts/ci/release-plan.sh`).

**Secrets** (Settings › Secrets and variables › Actions), all needed for signing; without them only
unsigned snapshots can be made:

| Secret | What |
|---|---|
| `MACOS_CERTIFICATE_P12` | The "Developer ID Application" certificate with its private key, exported from Keychain Access as .p12, then `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERTIFICATE_PASSWORD` | The password chosen when exporting it |
| `APPLE_ID` | The Apple Account of the developer team |
| `APPLE_TEAM_ID` | The team ID (10 characters) |
| `APPLE_APP_PASSWORD` | An app-specific password for that account (account.apple.com › Sign-In and Security) |

`scripts/ci/import-signing.sh` puts the certificate in a keychain of the job's own and stores notarytool's
credentials there; the job deletes it at the end.

**Variables** (same page, Variables tab), all optional:

| Variable | Default | What |
|---|---|---|
| `SIDEFOLK_MACOS_RUNNER` | `macos-26` | The runner image, e.g. `xcode-27` (the preview image with Xcode 27) |
| `SIDEFOLK_XCODE` | the image's default | An Xcode on that image, e.g. `26.6` (`/Applications/Xcode_26.6.app`) |
| `SIDEFOLK_KEEP_SNAPSHOTS` | `10` | How many snapshot releases to keep |

The project is developed with Xcode 27 (Swift 6.4) and needs at least the macOS 26 SDK (voice uses
SpeechAnalyzer) and Swift 6.2 (`Package.swift`). `macos-26` defaults to Xcode 26.6; if a build there fails on
a newer Swift feature, set `SIDEFOLK_MACOS_RUNNER` to `xcode-27`.

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
- [ ] A built-in extension runs in its sandbox (World Clock). On a Mac **without** Apple's developer tools:
      no "install the command line developer tools" dialog appears at launch, and Settings › Extensions says
      each built-in needs Python and how to get it (every built-in is a Python program today; see "Open
      decisions").
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

- **Built-ins on a clean Mac.** World Clock, System Vitals, Weather and Git are Python programs, and a Mac
  without Apple's Command Line Tools has no Python. Sidefolk now says so instead of failing (and never runs
  the `/usr/bin` shims that would offer the install), but those four don't work until the person installs the
  tools. Options: ship them as small compiled programs, or say "needs the Command Line Tools" on the website.

- **Intel Macs.** macOS 15 still runs on Intel Macs. A universal build doubles the binary size and needs one test
  on Intel (extensions' interpreters, sandbox-exec and the companion's rendering).
- **Updates.** Sparkle needs an EdDSA key and a hosted appcast; until then the README and the About window
  should say where new versions are announced.
- **Crash reports.** If wanted later: opt-in, local first (show the macOS crash log and let the person send it),
  consistent with "no telemetry".
