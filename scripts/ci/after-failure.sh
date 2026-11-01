#!/bin/bash
# After a test run fails on CI: what the system saw (launchd, jetsam, the kernel), crash reports, and
# the last process snapshots run-test-bundles.sh took. Usage: after-failure.sh "<UTC start>" <logs folder>
set -uo pipefail

since="$1" logs="$2"
section() { printf '\n== %s\n' "$*"; }

section "Memory and disk now"; memory_pressure -Q 2>/dev/null; vm_stat | head -8; df -h /
for status in "$logs"/*.status.pid; do
  [[ -e "$status" ]] || continue
  pid="$(cat "$status")"
  section "System log about pid $pid ($(basename "$status" .status.pid))"
  log show --last 10m --style compact --predicate "processID == $pid OR eventMessage CONTAINS \"[$pid]\" OR eventMessage CONTAINS \"pid $pid\" OR eventMessage CONTAINS \"($pid)\"" \
    > "$logs/log-pid-$pid.txt" 2>&1
  grep -v "^Filtering\|^Timestamp" "$logs/log-pid-$pid.txt" | tail -150
done

section "System log: launchd, xctest, jetsam, kills"
log show --last 10m --style compact --predicate \
  'process == "launchd" OR eventMessage CONTAINS "xctest" OR eventMessage CONTAINS "jetsam" OR eventMessage CONTAINS[c] "SidefolkCoreTests" OR eventMessage CONTAINS "swiftpm-testing-helper" OR (process == "kernel" AND (eventMessage CONTAINS[c] "kill" OR eventMessage CONTAINS[c] "memorystatus" OR eventMessage CONTAINS[c] "sandbox"))' \
  > "$logs/log-system.txt" 2>&1
grep -iE "SidefolkCoreTests|testing-helper|xctest|jetsam|memorystatus|killed|kill\(|signal|exited|crash" "$logs/log-system.txt" | tail -200

section "Crash reports since $since UTC"
marker="$(mktemp)"; touch -t "$(date -j -u -f '%Y-%m-%d %H:%M:%S' "$since" '+%Y%m%d%H%M.%S' 2>/dev/null || date '+%Y%m%d0000')" "$marker"
mkdir -p "$logs/crash-reports"
found=0
for dir in ~/Library/Logs/DiagnosticReports /Library/Logs/DiagnosticReports; do
  while IFS= read -r report; do
    [[ -n "$report" ]] || continue
    found=1
    echo "-- $report"; cp "$report" "$logs/crash-reports/" 2>/dev/null || sudo cp "$report" "$logs/crash-reports/"
    head -c 6000 "$report" 2>/dev/null || sudo head -c 6000 "$report"; echo
  done < <(sudo find "$dir" -type f -newer "$marker" 2>/dev/null)
done
(( found )) || echo "(none)"

section "The last process snapshots"
if [[ -f "$logs/processes.log" ]]; then
  awk '/^-- /{n++} {print n "\t" $0}' "$logs/processes.log" | awk -F'\t' -v last="$(grep -c '^-- ' "$logs/processes.log")" '$1 >= last - 2 {print $2}' \
    | grep -E "^-- |System-wide|Tests|testing-helper|swift-|sandbox|hdiutil|ext-|sidefolk" | head -120
fi
exit 0
