#!/usr/bin/env bash
# Explicit credentialed operation. Produces review artifacts only; never uploads a release.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { echo 'Requires Apple Silicon macOS' >&2; exit 1; }
node scripts/release-readiness.mjs
bash scripts/release-checks.sh
release_tmp=$(mktemp -d)
trap 'rm -rf "$release_tmp"' EXIT
node scripts/release-readiness.mjs --config > "$release_tmp/config.json"
export MACOSX_DEPLOYMENT_TARGET=14.0
export CARGO_TARGET_DIR="$PWD/src-tauri/target"
# Notarize explicitly below; never let Tauri choose a password-based path.
env -u APPLE_API_KEY -u APPLE_API_ISSUER -u APPLE_API_KEY_PATH \
  npx tauri build --ci --target aarch64-apple-darwin --bundles app --config "$release_tmp/config.json"
release_root=src-tauri/target/aarch64-apple-darwin/release
release_app="$release_root/bundle/macos/Sidefolk.app"
release_out="$release_root/p6"
mkdir -p "$release_out"
dsymutil "$release_root/sidefolk" -o "$release_out/sidefolk.dSYM"
[[ -s "$release_out/sidefolk.dSYM/Contents/Resources/DWARF/sidefolk" ]]
codesign --verify --deep --strict --verbose=2 "$release_app"
codesign -d --verbose=4 "$release_app" 2>&1 | tee "$release_out/codesign.txt"
# A valid ad-hoc signature is not a Developer ID release.
grep -q 'Authority=Developer ID Application:' "$release_out/codesign.txt"
grep -q 'flags=.*runtime' "$release_out/codesign.txt"
codesign -d --entitlements :- "$release_app" > "$release_out/entitlements.plist"
/usr/libexec/PlistBuddy -c 'Print :com.apple.security.automation.apple-events' "$release_out/entitlements.plist" | grep -qx true
if [[ -n "${SIDEFOLK_NOTARY_PROFILE:-}" ]]; then
  notary_args=(--keychain-profile "$SIDEFOLK_NOTARY_PROFILE")
else
  notary_args=(--key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY" --issuer "$APPLE_API_ISSUER")
fi
ditto -c -k --keepParent "$release_app" "$release_tmp/Sidefolk.zip"
xcrun notarytool submit "$release_tmp/Sidefolk.zip" "${notary_args[@]}" --wait
xcrun stapler staple "$release_app"
xcrun stapler validate "$release_app"
spctl --assess --type execute --verbose=2 "$release_app"
mkdir "$release_tmp/dmg"
ditto "$release_app" "$release_tmp/dmg/Sidefolk.app"
ln -s /Applications "$release_tmp/dmg/Applications"
hdiutil create -volname Sidefolk -srcfolder "$release_tmp/dmg" -format UDZO "$release_out/Sidefolk.dmg"
codesign --force --sign "$APPLE_SIGNING_IDENTITY" --timestamp "$release_out/Sidefolk.dmg"
xcrun notarytool submit "$release_out/Sidefolk.dmg" "${notary_args[@]}" --wait
xcrun stapler staple "$release_out/Sidefolk.dmg"
xcrun stapler validate "$release_out/Sidefolk.dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$release_out/Sidefolk.dmg"
# Repack after stapling: the update signature must cover the final app bytes.
tar -czf "$release_out/Sidefolk.app.tar.gz" -C "$(dirname "$release_app")" Sidefolk.app
release_version=$(node -p 'require("./src-tauri/tauri.conf.json").version')
if [[ -f "$TAURI_SIGNING_PRIVATE_KEY" ]]; then
  env -u TAURI_SIGNING_PRIVATE_KEY npx tauri signer sign --private-key-path "$TAURI_SIGNING_PRIVATE_KEY" --app-version "$release_version" "$release_out/Sidefolk.app.tar.gz"
else
  npx tauri signer sign --app-version "$release_version" "$release_out/Sidefolk.app.tar.gz"
fi
node --input-type=module - "$release_out" <<'JS'
import { readFileSync, writeFileSync } from 'node:fs';
import { problems, configuration } from './scripts/release-readiness.mjs';
const out = process.argv[2];
const config = configuration(JSON.parse(readFileSync('src-tauri/tauri.conf.json')), process.env);
if (problems(config).length) throw Error('Release configuration changed');
const version = config.version;
const minimum = process.env.SIDEFOLK_MIN_SAFE_VERSION;
// Runtime policy performs full SemVer validation; keep release generation stable-only.
if (!/^\d+\.\d+\.\d+$/.test(minimum || '')) throw Error('SIDEFOLK_MIN_SAFE_VERSION required');
const compare = (a,b) => a.split('.').map(Number).reduce((r,n,i) => r || Math.sign(n-Number(b.split('.')[i])),0);
if (compare(minimum, version) > 0) throw Error('Minimum exceeds release version');
const notes = readFileSync(process.env.SIDEFOLK_RELEASE_NOTES_FILE, 'utf8').trim();
if (!notes) throw Error('Release notes required');
const feed = config.plugins.updater.endpoints[0];
const url = feed.replace('/latest/download/latest.json', `/download/v${version}/Sidefolk.app.tar.gz`);
writeFileSync(`${out}/latest.json`, JSON.stringify({ version, min_safe_version: minimum, notes,
  pub_date: new Date().toISOString(), platforms: { 'darwin-aarch64': {
    url, signature: readFileSync(`${out}/Sidefolk.app.tar.gz.sig`, 'utf8').trim(),
  } } }, null, 2) + '\n');
JS
shasum -a 256 "$release_out/Sidefolk.dmg" "$release_out/Sidefolk.app.tar.gz" > "$release_out/SHA256SUMS"
echo "Review artifacts: $release_out. Nothing published; founder gates remain required."
