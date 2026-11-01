#!/bin/bash
# Runs each built test bundle the way `swift test --no-parallel` does (the toolchain's swiftpm-testing-helper,
# in a process group of its own), but on a terminal so every line reaches the log as it is written, and
# says how each process ended: its exit status, or the signal that ended it. A snapshot of the processes and
# memory every five seconds goes to <logs>/processes.log. Honours $FILTER and $SKIP like --filter and --skip.
# Usage: scripts/ci/run-test-bundles.sh <logs folder>   (after `swift build --build-tests`)
set -euo pipefail
cd "$(dirname "$0")/../.."

logs="$1"
mkdir -p "$logs"
helper="$(dirname "$(xcrun --find swift)")/../libexec/swift/pm/swiftpm-testing-helper"
[[ -x "$helper" ]] || { echo "run-test-bundles: no swiftpm-testing-helper at $helper" >&2; exit 1; }
bin="$(swift build --show-bin-path)"
# Where swift test finds XCTest and its support library (the bundles link them even for Swift Testing).
# macOS drops DYLD_ variables on the way through script(1) and /bin/bash, so the inner shell sets them.
export TEST_PLATFORM="$(xcrun --show-sdk-platform-path)/Developer"
# A crash's backtrace is printed and the process ends; it never waits for someone at the terminal.
export SWIFT_BACKTRACE="interactive=no"

watch_processes() {
  while :; do
    { date -u '+-- %H:%M:%S'; memory_pressure -Q 2>/dev/null | tail -1
      ps -U "$(id -u)" -o pid,ppid,pgid,stat,rss,etime,command | grep -vE ' (ps|grep|sleep|cut) ' | cut -c1-240; } >> "$logs/processes.log"
    sleep 5
  done
}
watch_processes &
watcher=$!
trap 'kill "$watcher" 2>/dev/null || true' EXIT

args=(--no-parallel)
[[ -n "${FILTER:-}" ]] && args+=(--filter "$FILTER")
[[ -n "${SKIP:-}" ]] && args+=(--skip "$SKIP")

failed=0
for bundle in "$bin"/*Tests.xctest; do
  name="$(basename "$bundle" .xctest)"
  binary="$bundle/Contents/MacOS/$name"
  printf '\n== %s (started %s UTC)\n' "$name" "$(date -u '+%H:%M:%S')"
  # set -m gives the helper its own process group, as swift test does; the status is written by the
  # shell that waited for it, since script(1) doesn't pass a signal on.
  STATUS="$logs/$name.status" script -q "$logs/$name.log" /bin/bash -c 'set -m
    export DYLD_FRAMEWORK_PATH="$TEST_PLATFORM/Library/Frameworks" DYLD_LIBRARY_PATH="$TEST_PLATFORM/usr/lib"
    "$@" & echo "$!" > "$STATUS.pid"; wait "$!"; echo "$?" > "$STATUS"' \
    _ "$helper" --test-bundle-path "$binary" "${args[@]}" "$binary" --testing-library swift-testing \
    < /dev/null > /dev/null &
  wait "$!" || true
  status="$(cat "$logs/$name.status" 2>/dev/null || echo "?")"
  pid="$(cat "$logs/$name.status.pid" 2>/dev/null || echo "?")"
  tr -d '\r' < "$logs/$name.log"
  if [[ "$status" == 0 ]]; then
    echo "== $name: exit 0 (pid $pid, ended $(date -u '+%H:%M:%S') UTC)"
  elif [[ "$status" =~ ^[0-9]+$ ]] && (( status > 128 )); then
    echo "::error title=$name died::killed by signal $((status - 128)) (SIG$(kill -l $((status - 128)))), pid $pid, at $(date -u '+%H:%M:%S') UTC"
    failed=1
  else
    echo "::error title=$name failed::exit status $status, pid $pid, at $(date -u '+%H:%M:%S') UTC"
    failed=1
  fi
done
exit "$failed"
