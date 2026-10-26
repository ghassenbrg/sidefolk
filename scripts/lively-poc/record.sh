#!/bin/zsh
# A real screen recording of the live window only (screencapture -l <window id>), on an opaque
# paper backdrop so nothing behind it shows. Needs Screen Recording for the terminal (checked first
# with CGPreflightScreenCaptureAccess, which never prompts).
# Usage: scripts/lively-poc/record.sh <id> <seconds> [live flags...]
set -u
cd "${0:A:h}/../.."
id=$1 secs=$2; shift 2
out=build/lively-poc/recordings
mkdir -p $out
name=$out/rec-${id:t}-$(date +%H%M%S)
.build/release/sidefolk-render --live demo $(( secs + 3 )) $id --backdrop "$@" > $name.log 2>&1 &
pid=$!
until grep -q "window [0-9]" $name.log 2>/dev/null; do sleep 0.2; done
win=$(grep -o "window [0-9]*" $name.log | head -1 | cut -d' ' -f2)
screencapture -x -v -V $secs -o -l$win $name.mov
wait $pid
echo "$name.mov"
