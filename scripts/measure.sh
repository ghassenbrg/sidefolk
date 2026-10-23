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
BIN=$(find "$APP/Contents/MacOS" -maxdepth 1 -type f -perm -u+x | head -1)
DATA=$(mktemp -d)

before=$(ps -axo pid= | sort -n)
SIDEFOLK_DATA_DIR="$DATA" "$BIN" >/dev/null 2>&1 &
MAIN=$!
trap 'kill $MAIN 2>/dev/null || true; rm -rf "$DATA"' EXIT
sleep "$WARMUP"

after=$(ps -axo pid= | sort -n)
pids=()
for pid in $(comm -13 <(echo "$before") <(echo "$after")); do
  cmd=$(ps -o comm= -p "$pid" 2>/dev/null || true)
  case "$cmd" in
    *"$APP"* | *com.apple.WebKit* | *Helper*) pids+=("$pid") ;;
  esac
done
[[ " ${pids[*]} " == *" $MAIN "* ]] || pids+=("$MAIN")

samples=$((SECONDS_TO_SAMPLE / 5 + 1))
args=()
for pid in "${pids[@]}"; do args+=(-pid "$pid"); done

echo "Sampling ${#pids[@]} processes for ${SECONDS_TO_SAMPLE}s: $APP"
top -l "$samples" -s 5 -stats pid,cpu,mem,command "${args[@]}" |
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
