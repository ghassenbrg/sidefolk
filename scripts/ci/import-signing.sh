#!/bin/bash
# For a GitHub runner: puts the Developer ID certificate from the repository's secrets in a keychain
# of its own and stores notarytool's credentials there, then prints identity= and keychain= for
# $GITHUB_OUTPUT. Never prints a secret. The workflow deletes the keychain when the job ends.
#
# Needs MACOS_CERTIFICATE_P12 (the certificate and its private key exported as .p12, base64),
# MACOS_CERTIFICATE_PASSWORD, APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD (an app-specific password)
# and RUNNER_TEMP.
set -euo pipefail
fail() { echo "import-signing: $*" >&2; exit 1; }
for name in MACOS_CERTIFICATE_P12 MACOS_CERTIFICATE_PASSWORD APPLE_ID APPLE_TEAM_ID APPLE_APP_PASSWORD RUNNER_TEMP; do
  [[ -n "${!name:-}" ]] || fail "$name is not set."
done

keychain="$RUNNER_TEMP/sidefolk-signing.keychain-db"
password="$(uuidgen)"
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$password" "$keychain"

certificate="$RUNNER_TEMP/developer-id.p12"
trap 'rm -f "$certificate"' EXIT
printf '%s' "$MACOS_CERTIFICATE_P12" | base64 --decode > "$certificate"
security import "$certificate" -k "$keychain" -P "$MACOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
# Lets codesign use the key without a prompt nobody is there to answer.
security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$keychain" >/dev/null
# codesign and `security find-identity` look through the user's search list; put this keychain on it.
existing=()
while IFS= read -r line; do existing+=("$(echo "$line" | tr -d ' "')"); done < <(security list-keychains -d user)
security list-keychains -d user -s "$keychain" "${existing[@]}"

xcrun notarytool store-credentials sidefolk-notary --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" --keychain "$keychain" >/dev/null

identity="$(security find-identity -v -p codesigning "$keychain" | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | sed -n 1p)"
[[ -n "$identity" ]] || fail 'the certificate holds no "Developer ID Application" identity.'
echo "identity=$identity"
echo "keychain=$keychain"
