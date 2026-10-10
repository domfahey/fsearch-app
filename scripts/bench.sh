#!/usr/bin/env bash
# Performance benchmarks with a regression check against bench/baseline.json.
#
#   scripts/bench.sh                 build (release), run, compare to this machine's baseline
#   scripts/bench.sh --record        run and rewrite this machine's baseline entry
#   scripts/bench.sh --record --provisional   same, marked provisional (noisy machine)
#   scripts/bench.sh --report-only   run and compare, never fail (CI)
#   scripts/bench.sh --self-test     simulate a 2x slowdown; the check must fail (exit 1)
#   scripts/bench.sh --skip-daemon   in-process metrics only
#   scripts/bench.sh --filter a,b    only metrics whose names start with a or b
#
# A metric fails (exit 1) only if its median regresses beyond its tolerance on
# the run and again on a re-run of just the regressed metrics. If a CPU canary
# shows the machine itself is slower, it waits and retries, then exits 75
# (inconclusive) rather than 1. Baselines are
# keyed by machine (hw.model + chip, or $BENCH_MACHINE); with no entry for this
# machine the run is reported without failing. See bench/README.md.
#
# A daemon that is too slow to answer (a timed-out sample is retried once, the
# index wait is bounded) gives an "inconclusive (daemon slow)" result: the
# metrics measured so far are kept, the rest are skipped, and the run exits 75
# (0 with --report-only).
#
# Safety: the daemon only ever runs with a temp HOME/FSEARCH_ROOT under a fresh
# /tmp/fsb.* directory, which this script removes on exit (and kills the daemon
# if it is still running).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PKG="$ROOT/Packages/FSearchKit"
BASELINE="$ROOT/bench/baseline.json"
RESULTS="$ROOT/bench/results"

RECORD=0 PROVISIONAL=0 REPORT_ONLY=0 SELF_TEST=0
PASS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --record) RECORD=1 ;;
    --provisional) PROVISIONAL=1 ;;
    --report-only) REPORT_ONLY=1; PASS+=(--report-only) ;;
    --self-test) SELF_TEST=1 ;;
    --skip-daemon) PASS+=(--skip-daemon) ;;
    --filter|--samples) PASS+=("$1" "$2"); shift ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    *) echo "bench.sh: unknown option $1" >&2; exit 64 ;;
  esac
  shift
done

# Short path (Unix socket paths max out at 104 bytes), with /tmp resolved to
# /private/tmp: the daemon content-indexes only under HOME, compared by real path.
WORK=$(cd "$(mktemp -d /tmp/fsb.XXXXXX)" && pwd -P)
cleanup() {
  local pid
  if [ -f "$WORK/daemon.pid" ]; then
    pid=$(cat "$WORK/daemon.pid")
    if kill -0 "$pid" 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null || true
      for _ in $(seq 50); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
      kill -KILL "$pid" 2>/dev/null || true
    fi
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

echo "==> building FSearchBench (release)"
(cd "$PKG" && swift build -c release --product FSearchBench 2>&1 | grep -vE '^\[[0-9]+/[0-9]+\]' || true)
BIN="$(cd "$PKG" && swift build -c release --show-bin-path)/FSearchBench"
[ -x "$BIN" ] || { echo "bench.sh: build failed" >&2; exit 1; }

MACHINE=${BENCH_MACHINE:-$("$BIN" machine-key)}
DAEMON=${FSEARCH_DAEMON:-$ROOT/Vendor/fsearch}

# Daemon revision: Vendor/fsearch.rev (written by build-daemon.sh), else the
# .rev next to a symlinked binary, else the pin in build-daemon.sh.
daemon_rev() {
  local rev="" target
  if [ -f "$ROOT/Vendor/fsearch.rev" ]; then
    rev=$(cat "$ROOT/Vendor/fsearch.rev")
  elif [ -L "$DAEMON" ]; then
    target=$(readlink "$DAEMON")
    [ -f "$(dirname "$target")/fsearch.rev" ] && rev="$(cat "$(dirname "$target")/fsearch.rev")"
  fi
  if [ -z "$rev" ]; then
    rev="pin:$(sed -nE 's/^REV=\$\{FSEARCH_REV:-([0-9a-f]+)\}.*/\1/p' "$ROOT/scripts/build-daemon.sh")"
  fi
  echo "$rev"
}
REV=$(daemon_rev)
XCODE=$(xcodebuild -version 2>/dev/null | paste -sd ' ' - || echo unknown)
SWIFTV=$(swift --version 2>&1 | head -1 || echo unknown)

mkdir -p "$RESULTS"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
[ "$SELF_TEST" = 1 ] && PASS+=(--self-test) && STAMP="$STAMP-selftest"

run_bench() {  # out-file, extra args...
  local out=$1; shift
  "$BIN" run --out "$out" --machine "$MACHINE" --daemon "$DAEMON" --daemon-rev "$REV" \
    --xcode "$XCODE" --swift "$SWIFTV" --work "$WORK" ${PASS[@]+"${PASS[@]}"} "$@"
}

OUT="$RESULTS/$STAMP-$MACHINE.json"
echo "==> running ($MACHINE)"
rc=0
run_bench "$OUT" || rc=$?
if [ "$rc" != 0 ]; then
  # Report-only never fails: keep whatever results were written and compare those.
  [ "$REPORT_ONLY" = 1 ] || exit "$rc"
  echo "==> report-only: the run ended early (exit $rc); not failing"
  [ -f "$OUT" ] || exit 0
fi

if [ "$RECORD" = 1 ]; then
  [ "$SELF_TEST" = 1 ] && { echo "bench.sh: refusing to record a self-test run" >&2; exit 64; }
  args=(record --baseline "$BASELINE" --current "$OUT" --machine "$MACHINE")
  [ "$PROVISIONAL" = 1 ] && args+=(--provisional)
  "$BIN" "${args[@]}"
  exit 0
fi

echo "==> comparing with bench/baseline.json"
rc=0
"$BIN" compare --baseline "$BASELINE" --current "$OUT" --machine "$MACHINE" --regressed-out "$WORK/regressed.txt" || rc=$?
case $rc in
  0) echo "==> PASS: no metric regressed beyond its tolerance"; exit 0 ;;
  2) echo "==> no baseline for $MACHINE: report only (record one with scripts/bench.sh --record)"; exit 0 ;;
  1) ;;
  *) echo "bench.sh: compare failed ($rc)" >&2; exit "$rc" ;;
esac

# Noise check: re-run only the regressed metrics. A metric fails only if it
# regresses again. If the CPU canary says the machine itself is slower than at
# baseline time, wait and retry (up to 3 re-runs) instead of blaming the code.
FILTER=$(paste -sd , "$WORK/regressed.txt")
for attempt in 1 2 3; do
  echo "==> regressed: $FILTER; re-running those to rule out noise (attempt $attempt)"
  OUT2="$RESULTS/$STAMP-$MACHINE-rerun$attempt.json"
  run_bench "$OUT2" --filter "$FILTER"
  rc=0
  "$BIN" compare --baseline "$BASELINE" --current "$OUT2" --machine "$MACHINE" \
    --regressed-out "$WORK/regressed2.txt" --busy-out "$WORK/busy.txt" || rc=$?
  if [ "$rc" != 1 ]; then echo "==> PASS: the first-run regressions did not reproduce (noise)"; exit 0; fi
  FILTER=$(paste -sd , "$WORK/regressed2.txt")
  [ -s "$WORK/busy.txt" ] || break
  if [ "$attempt" -lt 3 ]; then echo "==> machine busy (canary.cpu slower than at baseline); waiting 30 s"; sleep 30; fi
done
if [ -s "$WORK/busy.txt" ]; then
  echo "==> INCONCLUSIVE: still regressed ($FILTER), but the machine stayed busy (canary.cpu); rerun when it's quiet"
  [ "$REPORT_ONLY" = 1 ] && exit 0
  exit 75
fi
echo "==> FAIL: regressed on every run: $FILTER"
[ "$REPORT_ONLY" = 1 ] && { echo "==> report-only: not failing"; exit 0; }
exit 1
