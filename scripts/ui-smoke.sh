#!/bin/bash
# Runs the panel UI tests (AppUITests) against a throwaway daemon (temp HOME + root).
# Xcode's UI-test runner is sandboxed and cannot start the daemon itself.
# UI_ONLY=AppUITests/PanelUITests/testX narrows the run; UI_LOG=<file> keeps the log.
# Extra arguments go to xcodebuild (e.g. -enableCodeCoverage YES -resultBundlePath x).
# Exits non-zero if the daemon never comes up, a test fails, a test is
# skipped, no test ran, or the app wrote its search log outside the temp HOME.
set -u -o pipefail
cd "$(dirname "$0")/.." || exit 1
export DEVELOPER_DIR=${DEVELOPER_DIR:-$(xcode-select -p)}
H=/private/tmp/fsa-ui-$(openssl rand -hex 3)
LOG=$(mktemp -t ui-smoke)
SOCK="$H/Library/Application Support/FSearch/fsearch.sock"
REAL_LOG="$HOME/Library/Logs/FSearch/searches.jsonl"
TEST_LOG="$H/Library/Application Support/FSearch/searches.jsonl"

# Fixtures. Queries use words the temp folder's hex name can't contain.
R="$H/root/proj"
mkdir -p "$R/src" "$R/duo"
echo x > "$R/heronfile.txt"
echo x > "$R/🏡 zq wv.txt"
echo x > "$R/duo/plover-one.txt"
echo x > "$R/duo/plover-two.txt"
printf 'first line\nthe quokkaneedle line\nlast line\n' > "$R/notes.md"
printf 'import Foundation\n\nfunc kestrelHandler() -> Int {\n    return 1\n}\n' > "$R/src/kestrel.swift"

stamp() { if [ -e "$1" ]; then stat -f '%m %z' "$1"; else echo absent; fi; }
REAL_BEFORE=$(stamp "$REAL_LOG")

HOME=$H FSEARCH_ROOT=$H/root Vendor/fsearch serve >/dev/null 2>&1 & DP=$!
cleanup() {
  kill $DP 2>/dev/null
  for _ in $(seq 10); do kill -0 $DP 2>/dev/null || break; sleep 0.5; done
  kill -9 $DP 2>/dev/null
  wait $DP 2>/dev/null
  rm -rf "$H" "$LOG"
  # The app's test-mode defaults suite (AppDefaults.testSuiteName).
  rm -f "$HOME"/Library/Preferences/com.domfahey.fsearch.apptests.*.plist
}
trap cleanup EXIT
for _ in $(seq 50); do [ -S "$SOCK" ] && break; sleep 0.2; done
[ -S "$SOCK" ] || { echo "ui-smoke: daemon socket never appeared at $SOCK" >&2; exit 1; }

# TEST_RUNNER_* reach the test process without the prefix. UI_REQUIRED makes a
# missing socket a failure instead of a skip.
TEST_RUNNER_FSEARCH_SOCKET="$SOCK" TEST_RUNNER_FSEARCH_UI_REQUIRED=1 \
  xcodebuild test -project FSearch.xcodeproj -scheme FSearch -derivedDataPath build -only-testing:"${UI_ONLY:-AppUITests}" "$@" > "$LOG" 2>&1
rc=$?
[ -n "${UI_LOG:-}" ] && cp "$LOG" "$UI_LOG"   # keep the full xcodebuild log
grep -E "error:|\*\* TEST|Test Case '.*' (passed|failed|skipped)" "$LOG" | sort -u | cut -c1-400

# No false green: something must have run, and nothing may be skipped.
N=$(grep -cE "Test Case '.*' (passed|failed)" "$LOG")
SKIPPED=$(grep -cE "Test Case '.*' skipped" "$LOG")
if [ "$N" -eq 0 ]; then echo "ui-smoke: no tests ran" >&2; rc=1; fi
if [ "$SKIPPED" -ne 0 ]; then echo "ui-smoke: $SKIPPED test(s) skipped" >&2; rc=1; fi
echo "ui-smoke: $N test(s) ran, $SKIPPED skipped"

# Debug mode's search log must stay in the temp HOME.
if [ "$(stamp "$REAL_LOG")" != "$REAL_BEFORE" ]; then
  echo "ui-smoke: the app wrote the real $REAL_LOG" >&2; rc=1
fi
if grep -qE "testDebugModeShowsTimingAndLogsInTempHome.*passed" "$LOG"; then
  if [ -s "$TEST_LOG" ]; then echo "ui-smoke: debug search log stayed inside the temp HOME"
  else echo "ui-smoke: debug test ran but no search log at $TEST_LOG" >&2; rc=1; fi
fi
exit $rc
