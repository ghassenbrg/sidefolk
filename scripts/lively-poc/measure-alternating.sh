#!/bin/zsh
# The companion's cost on a busy desktop: one process keeps running while its window is hidden and
# shown every 10 s; the difference between the halves is the companion's share, for WindowServer's
# CPU (top), the companion's own CPU, and the whole GPU's utilization (ioreg, no sudo). Drift and
# other apps cancel out over many short turns. Release builds.
# Usage: scripts/lively-poc/measure-alternating.sh [seconds per condition] [conditions...]
set -u
cd "${0:A:h}/../.."
secs=${1:-240}
[ $# -gt 0 ] && shift
out=build/lively-poc/cpu/alternating
mkdir -p $out
ws=$(pgrep -x WindowServer | head -1)

condition() { # name, then the command
  local name=$1; shift
  "$@" > $out/$name.out 2>&1 & local pid=$!
  ( while kill -0 $pid 2>/dev/null; do
      echo "$(date +%H:%M:%S) $(ioreg -r -d 1 -w 0 -c IOAccelerator | grep -o '"Device Utilization %"=[0-9]*' | head -1 | cut -d= -f2)"
      sleep 2
    done ) > $out/$name.gpu &
  local sampler=$!
  sleep 1
  top -l $(( secs / 2 )) -s 2 -pid $ws -pid $pid -stats pid,command,cpu > $out/$name.top 2>&1
  kill $pid 2>/dev/null; wait $pid 2>/dev/null; wait $sampler 2>/dev/null
  python3 -I - $out/$name.top $out/$name.out $out/$name.gpu $ws $pid $name <<'PY' | tee -a $out/summary.txt
import re, sys
top, log, gpu, ws, pid, name = sys.argv[1:7]
def secs(hms): h, m, s = map(int, hms.split(':')); return h * 3600 + m * 60 + s
switches = [(secs(m.group(1)), m.group(2)) for m in re.finditer(r'\[alternate\] (\d\d:\d\d:\d\d) (shown|hidden)', open(log).read())]
def phase_of(when):
    # A top sample covers the 2 s before it: skip the 3 s after each switch.
    if any(0 <= when - s[0] < 3 for s in switches): return None
    past = [s for s in switches if s[0] <= when]
    return past[-1][1] if past else None
cpu = {('shown', ws): [], ('hidden', ws): [], ('shown', pid): [], ('hidden', pid): []}
t = None
for line in open(top):
    m = re.match(r'\d{4}/\d\d/\d\d (\d\d:\d\d:\d\d)', line)
    if m: t = secs(m.group(1)); continue
    parts = line.split()
    if t is not None and len(parts) >= 3 and parts[0] in (ws, pid) and phase_of(t):
        cpu[(phase_of(t), parts[0])].append(float(parts[2]))
gpus = {'shown': [], 'hidden': []}
for line in open(gpu):
    parts = line.split()
    if len(parts) == 2 and phase_of(secs(parts[0])): gpus[phase_of(secs(parts[0]))].append(float(parts[1]))
mean = lambda xs: sum(xs) / len(xs) if xs else float('nan')
w = mean(cpu[('shown', ws)]) - mean(cpu[('hidden', ws)])
g = mean(gpus['shown']) - mean(gpus['hidden'])
print(f"{name:26} WindowServer {w:+5.1f}% of a core ({mean(cpu[('shown', ws)]):.1f} shown, {mean(cpu[('hidden', ws)]):.1f} hidden)"
      f" | GPU {g:+5.1f} pts ({mean(gpus['shown']):.1f}/{mean(gpus['hidden']):.1f})"
      f" | app {mean(cpu[('shown', pid)]):.2f}% shown, {mean(cpu[('hidden', pid)]):.2f}% hidden"
      f" | {len(cpu[('shown', ws)])}/{len(cpu[('hidden', ws)])} samples")
PY
}

R=.build/release/sidefolk-render
conditions=("$@")
[ ${#conditions} -eq 0 ] && conditions=(2d-moments 2d-breathing 2d-breathing-robot 3d-alive)
for c in $conditions; do
  case $c in
    2d-moments) condition 2d-moments-nonstop $R --live demo 600 mochi --alternate 10 ;;
    2d-breathing) condition 2d-breathing-mochi $R --live idle 600 mochi --alternate 10 ;;
    2d-breathing-robot) condition 2d-breathing-robot $R --live idle 600 sidefolk --alternate 10 ;;
    2d-settled) condition 2d-settled-mochi $R --live idle 600 mochi --alternate 30 ;;
    3d-alive) condition 3d-alive .build/release/sidefolk-3d --live 600 --alternate 10 ;;
  esac
done
