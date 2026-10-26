#!/bin/bash
# Decides what a run of .github/workflows/release.yml makes, and prints it as key=value lines for
# $GITHUB_OUTPUT. Runs anywhere, so a plan can be checked before pushing a tag.
#
#   production  the version in Sources/SidefolkCore/Version.swift, tagged v<version>; must be signed
#               and notarized. A pushed tag v* is always production and must match that version.
#   snapshot    a prerelease of the commit, tagged v<version>-snapshot.<build> (build = commit count);
#               signed and notarized when the secrets are there, ad hoc signed otherwise.
#
# Reads GITHUB_REF, CHANNEL (from the run's input or the repository variable; default snapshot) and
# SIGNING (yes when the Developer ID secrets are set).
set -euo pipefail
cd "$(dirname "$0")/../.."
fail() { echo "release-plan: $*" >&2; exit 1; }

version="$(sed -n 's/.*current = "\(.*\)".*/\1/p' Sources/SidefolkCore/Version.swift)"
[[ -n "$version" ]] || fail "no version in Sources/SidefolkCore/Version.swift"
build="$(git rev-list --count HEAD)"
channel="${CHANNEL:-}"

if [[ "${GITHUB_REF:-}" == refs/tags/v* ]]; then
  tag="${GITHUB_REF#refs/tags/}"
  [[ "$tag" == "v$version" ]] || fail "the tag $tag doesn't match the app's version $version; change Version.swift or the tag."
  [[ -z "$channel" || "$channel" == production ]] || fail "a version tag makes a production release, not $channel."
  channel=production
fi
channel="${channel:-snapshot}"

case "$channel" in
  production)
    tag="v$version"; label=""; prerelease=false
    [[ "${SIGNING:-no}" == yes ]] || fail "a production release must be signed and notarized: add the Developer ID secrets (docs/RELEASE.md)."
    # A version is released once: a tag already on another commit means Version.swift wasn't raised.
    if existing="$(git rev-parse -q --verify "refs/tags/$tag^{commit}")" && [[ "$existing" != "$(git rev-parse HEAD)" ]]; then
      fail "$tag already marks another commit; raise the version in Version.swift first."
    fi
    ;;
  snapshot)
    tag="v$version-snapshot.$build"; label="snapshot.$build"; prerelease=true ;;
  *)
    fail "unknown channel \"$channel\": production or snapshot." ;;
esac

echo "channel=$channel"
echo "version=$version"
echo "build=$build"
echo "tag=$tag"
echo "label=$label"
echo "prerelease=$prerelease"
echo "dmg=build/Sidefolk-$version${label:+-$label}.dmg"
