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
  `SIDEFOLK_RELEASE_LABEL` names the image `Sidefolk-<version>-<label>.dmg`, and the release the app says it is
  (`SidefolkRelease` in Info.plist, `<version>-<label>`, stamped by `build-app.sh` when `SIDEFOLK_RELEASE=1`;
  the script refuses an app whose stamp differs, see "Updates" below); `SIDEFOLK_NOTARY_KEYCHAIN` points
  notarytool at a keychain other than the login one (CI). It prints each phase and each submission ID, and
  gives Apple `SIDEFOLK_NOTARY_MINUTES` (180) across both submissions, asking again after a network blip (each timestamped signature is tried up to five times too): a
  new team's first submissions can wait over an hour. The Release job's 210-minute limit covers that wait.
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

The team is `2XQJWQBD4W` ("Ghassen Bargougui", an individual membership). `4YY3SMSAS3` in "Apple Development:
… (4YY3SMSAS3)" names the person, not the team. The Developer ID certificate made on 2026-10-27 expires on
**2027-02-01**, with the original Developer ID authority (G1) that issued it: builds signed with a timestamp
and notarized before then keep opening, but releases after it need a new certificate in Xcode and new
`MACOS_CERTIFICATE_P12` and `MACOS_CERTIFICATE_PASSWORD` secrets.

**Variables** (same page, Variables tab), all optional:

| Variable | Default | What |
|---|---|---|
| `SIDEFOLK_MACOS_RUNNER` | `xcode-27` | The runner image (`xcode-27` is GitHub's image with Xcode 27; `macos-26` has Xcode 26) |
| `SIDEFOLK_XCODE` | the image's default | An Xcode on that image, e.g. `26.6` (`/Applications/Xcode_26.6.app`) |
| `SIDEFOLK_KEEP_SNAPSHOTS` | `10` | How many snapshot releases to keep |

The project is built with Xcode 27 (Swift 6.4), so both workflows run on GitHub's `xcode-27` image. It needs
at least the macOS 26 SDK (voice uses SpeechAnalyzer). Xcode 26.6 (`macos-26`, Swift 6.3.3) compiles the
debug build and passes the tests since three fixes for it, but its optimizer crashes on the release build
(in `HostedPanel`'s deinit), a compiler bug; prefer `xcode-27` until Swift 6.3 is no longer worth supporting.

## Updates (D46, D70)

A published Sidefolk looks for a newer one itself and asks before installing it, or installs it by itself at a
calm moment when the person chose that (D70). There is no update server and
no key to keep: the feed is this repository's GitHub Releases, and trust is the Developer ID signature.

- **What a release must keep doing**, or copies in the field stop updating: tags `v<version>` and
  `v<version>-snapshot.<build>`; the assets `Sidefolk-<release>.dmg` and `Sidefolk-<release>.dmg.sha256` (as
  `package.sh` writes them); the app at the top of the image named `*.app`, alone; bundle id
  `app.sidefolk.Sidefolk`; `SidefolkRelease` equal to the release (`release.sh` checks it); signed with this
  team's Developer ID (a new certificate of the same team is fine) and notarized. Snapshots are prereleases.
- **Who gets what.** A copy looks a minute after launch (unless it looked within the hour) and once a day, unless
  Settings › General › Updates › New versions of Sidefolk is Don't check; "Check for Updates…" is in the menu
  bar. On Tell me (the default) it asks; on Install automatically it downloads and checks the version as Update
  does, then swaps it in once the person has been away five minutes with nothing running (no conversation,
  approval, voice, Ask panel or job), or as they quit, and the new copy says "Updated to …" once. Every copy
  offers releases only unless Versions to offer says snapshots too (D52). Versions sort as
  semver: every snapshot of 0.1.0 comes before 0.1.0, so **raise `Version.swift` right after a production
  release**, or the next snapshots sort below it and nobody is offered them.
- **What it does on Update**: downloads the image, checks size and both checksums, mounts it hidden, checks the
  app inside (bundle id, release, Developer ID of the same team, notarized), copies it beside the running app
  as `.Sidefolk-update-<release>.app`, checks the copy, removes its download mark, swaps the two in one rename,
  quits and reopens. A copy that can't replace itself (built locally, not Developer ID, translocated, on the
  disk image, in a folder the account can't write) gets the checked image in Downloads instead. SECURITY T31.
- **Release notes** are what the update window shows. Production uses `docs/RELEASE-NOTES.md`; a snapshot's
  notes list the commit subjects since the previous release or snapshot it builds on.
- **Proving a release's update path.** The first snapshot carrying the updater must be installed by hand. Then,
  for each later release: install the previous one in /Applications from its DMG, open it, choose "Check for
  Updates…", Update and Restart; it reopens as the new version (About shows the build) with no Gatekeeper
  question, and no `.Sidefolk-update-*` folder is left in /Applications. The log's `"cat":"updates"` lines say
  what happened. On Install automatically, the same proof without a click: leave the Mac alone five minutes after
  the look (or quit Sidefolk), and the log says `installing by itself`, `calm moment: installing` (or `installed at
  quit`) and, after the reopen, `opened after installing by itself`. `SIDEFOLK_LIVE_NETWORK=1 swift test --filter livePublishedImageChecksOut` downloads the newest
  image and runs every check but the swap.

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
- [ ] `codesign -d --entitlements - build/Sidefolk.app`: only `com.apple.security.automation.apple-events`,
      `com.apple.security.device.audio-input` and `com.apple.security.personal-information.location` (D48). No
      `get-task-allow`, no library-validation or JIT exceptions (SECURITY T22).
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
- [ ] Built-in extensions run in their sandbox (World Clock, Calculator, Images on a photo). On a Mac **without**
      Apple's developer tools: no "install the command line developer tools" dialog appears at launch, every
      built-in but Git works, and Settings › Extensions says Git needs Git and how to get it.
- [ ] Quit and relaunch: reminders and watchers survive; the fallback notifications fire while it is quit.
- [ ] The update path from the previous release ("Updates" above): it offers this one, installs it and reopens.
- [ ] Idle: `top -l 1 -pid $(pgrep -x Sidefolk)` shows ~0 % CPU after the companion settles (see D41 for the
      numbers measured on the dev Mac).

**Publishing**
- [ ] Tag `v<version>` on the released commit; upload the DMG and its `.sha256` (GitHub Releases or the site).
- [ ] Release notes say Apple silicon only unless a universal build was tested on Intel.
- [ ] Keep the DMG and the notarization submission id with the tag.
- [ ] After a production release, raise `Version.swift` before the next snapshot (D46).

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
| Updates | Built (D46, replaces D15): GitHub Releases as the feed, Developer ID and notarization as the trust, asks before installing. The swap itself is proven only by the second release that carries it |
| Crash reporting | None (no telemetry). macOS keeps crash logs in `~/Library/Logs/DiagnosticReports`; ask people to attach the one named Sidefolk with the diagnostics export |
| DMG background, volume icon, licence in the DMG | Not done (plain DMG) |

## Open decisions

- **Intel Macs.** macOS 15 still runs on Intel Macs. A universal build doubles the binary size and needs one test
  on Intel (extensions' interpreters, sandbox-exec and the companion's rendering).
- **Crash reports.** If wanted later: opt-in, local first (show the macOS crash log and let the person send it),
  consistent with "no telemetry".
