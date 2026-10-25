#!/usr/bin/env bash
# Compile the owned module without editing the lead's main.rs or launching the app.
set -euo pipefail
cd "$(dirname "$0")/.."
policy_root=$PWD
policy_tmp=$(mktemp -d)
trap 'rm -rf "$policy_tmp"' EXIT
cp src-tauri/Cargo.toml src-tauri/Cargo.lock "$policy_tmp/"
printf '\n[lib]\npath = "%s/src-tauri/src/release.rs"\n' "$policy_root" >> "$policy_tmp/Cargo.toml"
cargo test --locked --lib --manifest-path "$policy_tmp/Cargo.toml" --target-dir "$policy_root/src-tauri/target"
