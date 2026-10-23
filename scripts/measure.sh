#!/usr/bin/env bash
# Measures CPU and memory of a desktop app and every helper process it spawns
# (WebKit content/GPU/network processes for Tauri, helper processes for Electron).
#
#   scripts/measure.sh [path/to/App.app] [seconds]
#
# The app is launched with a throwaway data directory and quit afterwards.
set -euo pipefail

APP=${1:-src-tauri/target/release/bundle/macos/Sidefolk.app}
SECONDS_TO_SAMPLE=${2:-60}
WARMUP=15

screen_unlocked() {
  ioreg -n Root -d1 -a | plutil -convert json -o - -- - | node -e '
    let text = "";
    process.stdin.on("data", chunk => text += chunk);
    process.stdin.on("end", () => {
      const locks = [];
      let onConsole = false;
      function walk(value) {
        if (!value || typeof value !== "object") return;
        if (value.kCGSSessionOnConsoleKey === true) onConsole = true;
        if (Object.hasOwn(value, "CGSSessionScreenIsLocked")) locks.push(value.CGSSessionScreenIsLocked);
        Object.values(value).forEach(walk);
      }
      walk(JSON.parse(text));
      // macOS removes the lock flag when unlocked. Require an active console session
      // and reject any explicit lock rather than requiring a false flag to exist.
      process.exit(onConsole && locks.every(locked => locked === false) ? 0 : 1);
    });'
}
if ! screen_unlocked; then
  echo "Unlock the screen before measuring visible CPU." >&2
  exit 1
fi
if lsof -nP -iTCP:47821 -sTCP:LISTEN -t >/dev/null 2>&1; then
  echo "Stop the running Sidefolk instance (port 47821) before measuring." >&2
  exit 1
fi
BIN=$(find "$APP/Contents/MacOS" -maxdepth 1 -type f -perm -u+x | head -1)
DATA=$(mktemp -d)

# Keep the benchmark awake even if the user has been idle before launch, and isolate
# the hook installer too: a menu click during measurement must not edit real settings.
echo '{"sleep_after_secs":86400}' > "$DATA/settings.json"
echo '{}' > "$DATA/claude-settings.json"
before=$(ps -axo pid= | sort -n)
SIDEFOLK_DATA_DIR="$DATA" SIDEFOLK_CLAUDE_SETTINGS="$DATA/claude-settings.json" "$BIN" >"$DATA/app.log" 2>&1 &
MAIN=$!
WATCHER=""
cleanup() {
  if [[ -n "$WATCHER" ]]; then kill "$WATCHER" 2>/dev/null || true; fi
  kill "$MAIN" 2>/dev/null || true
  rm -rf "$DATA"
}
trap cleanup EXIT
(
  while kill -0 "$MAIN" 2>/dev/null; do
    if ! screen_unlocked; then touch "$DATA/invalid"; fi
    sleep 5
  done
) &
WATCHER=$!
sleep "$WARMUP"
if ! kill -0 "$MAIN" 2>/dev/null; then cat "$DATA/app.log" >&2; exit 1; fi

after=$(ps -axo pid= | sort -n)
pids=()
for pid in $(comm -13 <(echo "$before") <(echo "$after")); do
  cmd=$(ps -o comm= -p "$pid" 2>/dev/null || true)
  case "$cmd" in
    *"$APP"* | *com.apple.WebKit* | *com.apple.audio.SandboxHelper*) pids+=("$pid") ;;
  esac
done
[[ " ${pids[*]} " == *" $MAIN "* ]] || pids+=("$MAIN")

samples=$((SECONDS_TO_SAMPLE / 5 + 1))
args=()
for pid in "${pids[@]}"; do args+=(-pid "$pid"); done

echo "Sampling ${#pids[@]} processes for ${SECONDS_TO_SAMPLE}s (visible, awake): $APP"
top -l "$samples" -s 5 -stats pid,cpu,mem,command "${args[@]}" > "$DATA/samples"
if [[ -f "$DATA/invalid" ]] || ! screen_unlocked; then
  echo "Screen locked during measurement; discard this run and retry unlocked." >&2
  exit 1
fi
cat "$DATA/samples" |
  awk -v n="$samples" '
    /^PID/ { sample++; next }
    sample >= 2 && $1 ~ /^[0-9]+$/ {
      cpu[$1] += $2; name[$1] = $4
      mem[$1] = $3
    }
    function mb(v) {
      if (v ~ /G/) return v * 1024
      if (v ~ /M/) return v + 0
      if (v ~ /K/) return v / 1024
      return v / 1048576
    }
    END {
      printf "%-8s %-40s %8s %10s\n", "PID", "PROCESS", "CPU%", "MEM(MB)"
      for (p in cpu) {
        c = cpu[p] / (n - 1); m = mb(mem[p])
        printf "%-8s %-40s %8.1f %10.1f\n", p, name[p], c, m
        tc += c; tm += m
      }
      printf "%-8s %-40s %8.1f %10.1f\n", "", "TOTAL", tc, tm
    }'
