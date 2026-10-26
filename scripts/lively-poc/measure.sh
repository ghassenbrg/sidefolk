#!/bin/zsh
# CPU per liveliness level: release sidefolk-render --live idle <secs> <id> --liveliness <level>,
# sampled with top every 2 s (the app and WindowServer). Writes cpu-<level>-<id>.log and a summary.
# Usage: scripts/lively-poc/measure.sh [seconds] [id] [extra live flags...]
set -u
cd "${0:A:h}/../.."
secs=${1:-240}
id=${2:-mochi}
shift 2 2>/dev/null
extra=("$@")
render=.build/release/sidefolk-render
out=build/lively-poc/cpu
mkdir -p $out
ws=$(pgrep -x WindowServer | head -1)
summary=$out/summary-$id.txt
: > $summary
for level in minimal balanced lively; do
  $render --live idle $secs $id --liveliness $level "${extra[@]}" > $out/live-$level-$id.log 2>&1 &
  pid=$!
  sleep 1
  samples=$(( (secs - 4) / 2 ))
  top -l $samples -s 2 -pid $pid -pid $ws -stats pid,command,cpu,mem,threads > $out/cpu-$level-$id.log 2>&1
  wait $pid
  # Skip top's first sample (it has no interval yet).
  app=$(awk -v p=$pid '$1==p {n++; if (n>1) {s+=$3; c++; if ($3>m) m=$3}} END {printf "%.2f avg, %.1f peak, %d samples", s/c, m, c}' $out/cpu-$level-$id.log)
  win=$(awk -v p=$ws '$1==p {n++; if (n>1) {s+=$3; c++; if ($3>m) m=$3}} END {printf "%.2f avg, %.1f peak", s/c, m}' $out/cpu-$level-$id.log)
  mem=$(awk -v p=$pid '$1==p {m=$4} END {print m}' $out/cpu-$level-$id.log)
  moments=$(grep -c "·" $out/live-$level-$id.log)
  echo "$level: app $app, mem $mem | WindowServer $win | 5 s checks with a moment playing: $moments" | tee -a $summary
done
