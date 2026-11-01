#!/bin/bash
# What a CI machine offers a test run: system, limits, memory, disk. Printed before the tests so a run that
# dies can be compared with one that doesn't (.github/workflows/ci-tests.yml).
set -uo pipefail

section() { printf '\n== %s\n' "$*"; }
section "System"; sw_vers; uname -a; sysctl -n machdep.cpu.brand_string hw.ncpu hw.memsize
section "Limits (soft)"; ulimit -a
section "Limits (hard)"; ulimit -Ha
section "Kernel limits"; sysctl kern.maxproc kern.maxprocperuid kern.maxfiles kern.maxfilesperproc
section "launchd limits"; launchctl limit 2>/dev/null || true
section "Memory"; memory_pressure -Q 2>/dev/null || true; vm_stat
section "Swap"; sysctl vm.swapusage
section "Disk"; df -h / "${RUNNER_TEMP:-/tmp}" "$PWD"
section "Crash reporting"; defaults read com.apple.CrashReporter 2>/dev/null || echo "(defaults)"
