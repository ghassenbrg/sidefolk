#!/usr/bin/env bash
# No ignored/live-agent tests. WebKit is mandatory; own the preview process and clean it up.
set -euo pipefail
cd "$(dirname "$0")/.."
npm run typecheck
npm test
cargo test --locked --manifest-path src-tauri/Cargo.toml
cargo clippy --locked --manifest-path src-tauri/Cargo.toml --all-targets -- -D warnings
node --test scripts/release-*.check.mjs
bash scripts/release-policy-tests.sh
# These checks include the Quick add corpus and voice-table tests in Vitest.
preview_port=1439
SIDEFOLK_CHECK_PORT="$preview_port" node --input-type=module -e 'import {createServer} from "vite"; const server = await createServer({server:{host:"127.0.0.1",port:Number(process.env.SIDEFOLK_CHECK_PORT),strictPort:true,hmr:false}}); await server.listen();' > "${TMPDIR:-/tmp}/sidefolk-release-web-$$.log" 2>&1 &
preview_pid=$!
trap 'kill "$preview_pid" 2>/dev/null || true' EXIT
for attempt in {1..60}; do
  kill -0 "$preview_pid" || { echo 'Preview failed to start' >&2; exit 1; }
  if curl --fail --silent "http://127.0.0.1:$preview_port/" > /dev/null; then break; fi
  sleep 1
done
curl --fail --silent "http://127.0.0.1:$preview_port/" > /dev/null
export SIDEFOLK_WEB="http://127.0.0.1:$preview_port"
npm run check:webkit
npm run check:webkit:p5

npm run check:reminders
