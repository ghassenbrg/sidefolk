#!/usr/bin/env bash
# Preserve the old entry point while requiring the reviewed, credential-gated release path.
set -euo pipefail
exec bash "$(dirname "$0")/release-build.sh" "$@"
