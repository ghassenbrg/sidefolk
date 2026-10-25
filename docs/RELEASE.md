# Releasing Sidefolk

P6 implementation, 25 October 2026; **not release ready**. No signed build, certificate import,
notarization, installation or publication has been performed by this work. G1–G5 remain founder
checks on a signed build in a clean macOS user account (V1 §12). Decision 48 authorizes the
native updater dependency; no Codex approval handling is added.

## Commands and artifacts

- `bash scripts/release-checks.sh`: typecheck, Vitest (including corpus/voice), locked Rust tests,
  strict Clippy, offline release-policy tests, both mandatory WebKit suites. Starts its own
  preview on 1439, fails if unavailable, cleans up its process. Never runs ignored CLI/model tests.
- `node scripts/release-readiness.mjs`: exits nonzero for missing real configuration, secrets or
  lead wiring review. No network, keychain changes or build. It does not certify gates.
- `bash scripts/release-build.sh`: credentialed Apple Silicon build targeting macOS 14.0;
  runs every check, signs/verifies Developer ID + hardened runtime + AppleEvents, archives dSYMs,
  notarizes/staples the app, builds/signs/notarizes/staples the DMG, then signs the final updater
  archive. Requires installed signing identity locally; never imports certificates locally.
- Output: `src-tauri/target/aarch64-apple-darwin/release/p6/`: `Sidefolk.dmg`,
  `Sidefolk.app.tar.gz`, `.sig`, `latest.json`, `SHA256SUMS`, `sidefolk.dSYM`, signing evidence.
  Keep dSYMs privately with the commit hash. Preserve these exact bytes when distributing.
- **The historical `scripts/release.sh` now delegates to the checked release-build path.**
  It can no longer skip WebKit or use password-based notarization. `npm run build` is a local build, not release-readiness evidence.

## Configuration and credentials

The checked-in updater has an empty public key, no endpoints and updater artifacts disabled.
Development remains possible; release-readiness fails. Never substitute a pretend key/feed.
Release builds use a temporary merged configuration; nothing writes back keys or endpoints.

Configure the GitHub **release** environment with required reviewers. `ci.yml` has no secrets.
`release.yml` runs only on manual dispatch, imports a certificate into a temporary runner
keychain, deletes it afterwards, and stores review artifacts. It has read-only repository
permissions and never creates a GitHub Release. Run only trusted reviewed revisions.

Secrets:

| Name | Value |
|---|---|
| `APPLE_CERTIFICATE` | Base64 Developer ID Application `.p12`, CI only |
| `APPLE_CERTIFICATE_PASSWORD` | Export password, CI only |
| `APPLE_SIGNING_IDENTITY` | Real `Developer ID Application: …` identity |
| `APPLE_API_KEY`, `APPLE_API_ISSUER` | App Store Connect team API key ID and issuer |
| `NOTARY_API_KEY` | `.p8` contents, CI only; materialized as mode-0600 temporary file |
| `TAURI_SIGNING_PRIVATE_KEY` | Tauri updater signing key contents (or local path) |
| `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` | Updater key password; empty only for an unencrypted key |

Environment variables / GitHub environment variables:

| Name | Value |
|---|---|
| `SIDEFOLK_UPDATER_PUBLIC_KEY` | Actual Tauri generated public key contents, not a filename |
| `SIDEFOLK_RELEASE_FEED` | Real `https://github.com/OWNER/REPO/releases/latest/download/latest.json` |
| `SIDEFOLK_MIN_SAFE_VERSION` | Stable SemVer minimum, no greater than release version |
| `SIDEFOLK_RELEASE_NOTES_FILE` | Repository-relative UTF-8 release notes file, Pip's voice |
| `SIDEFOLK_RELEASE_WIRING_REVIEWED` | `1` only after lead verifies all wiring below |

Locally, replace API credentials with `SIDEFOLK_NOTARY_PROFILE`, an existing `notarytool`
keychain profile. Alternatively supply `APPLE_API_KEY`, `APPLE_API_ISSUER` and
`APPLE_API_KEY_PATH` to an existing `.p8`. No `APPLE_ID`/`APPLE_PASSWORD` environment flow.
Generate/manage keys yourself outside the repo; keep backups of the updater key. Losing it
breaks updates for installed clients. No secret is needed for CI/tests.

## Native wiring implemented

`main.rs` registers the official updater plugin and native update commands. `updates.rs` owns
one gate around hold creation and answer resolution. A valid check persists the greatest known
minimum before publishing the policy; an invalid/offline response releases pending holds.
Pause answers is separate, persisted and cannot bypass the minimum. An unconfigured release
build cannot hold approvals (only an unconfigured debug build bypasses the feed requirement).

Launch, daily and manual checks retain offers in Rust, including equal-version safety checks.
Settings displays the offer and notes; install requires its exact offer ID, an authorized window
and a native confirmation. The plugin checks the signed archive/version. Restart is separately
confirmed. Renderer arguments cannot supply an artifact URL, signature or substitute consent.

Corrupt policy is quarantined and remains blocked on subsequent restarts, including when only
its quarantine/backup remains. Explicit restoration plus a fresh valid check is required.
Regression tests cover policy rollback, multiple restarts, pending release and late answers.
An independent review found the restart-floor issue and verified its correction. This is code
review evidence, not a successful real signed update. Set the wiring-reviewed attestation only
for the specific reviewed release revision.

`latest.json` contains `version`, `min_safe_version`, `notes`, `pub_date`, and
`platforms.darwin-aarch64.{url,signature}`. Artifact URLs point to `v<VERSION>` release assets.
The plugin signature authenticates the **archive** and its signed app version
(`requireSignedVersion`), not the extra JSON metadata. Policy metadata
relies on GitHub HTTPS/account security; the greatest observed minimum cannot be lowered by a
subsequent feed. Checks send no user/session data. Offline or unconfigured means no holds;
reminders/logging continue. Persisted minimum alone is insufficient to re-enable approvals.

## Verification / remaining gates

Offline policy tests compile the new module via a temporary library manifest without touching
main.rs, starting an app, calling a model/agent CLI or writing real configs. Browser captures
are preview-only; no desktop capture is used. CI isolates all config/data paths in runner temp.

Current verification is recorded in [the implementation check](checks/RELEASE-READINESS-2026-10-25.md).
Strict Clippy includes every target, without warning suppression. Socket buffered replies have
an explicit macOS regression; original forwarding, malformed and oversized reply tests remain.
No ignored CLI/model tests are part of this command.

Signing, notarization, real updater installation and GitHub-hosted workflows remain unexecuted.
The readiness command currently fails for missing real keys, identity, feed, minimum version,
release notes and revision attestation. No certificate, account or credentials were fabricated.

Before distribution, supply those inputs, archive symbols and record G1/G2-core/G2-agent/G3/G4/G5
against the signed build hash. G5 includes a downloaded DMG Gatekeeper check, an actual update
preserving data, byte-identical unrelated config preservation on uninstall, and green release CI.
Then run the four-week P7 cohorts and evaluate the contract's targets before P8 publication.
These human/native/cohort gates are not passed by scripts or an agent. Nothing was published.

Official references: [Tauri updater](https://v2.tauri.app/plugin/updater/),
[Tauri macOS signing](https://v2.tauri.app/distribute/sign/macos/),
[GitHub runner labels](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
