#!/bin/bash
# Runs the panel UI smoke test against a throwaway daemon (temp HOME + root).
# Xcode's UI-test runner is sandboxed and cannot start the daemon itself.
# Exits non-zero if the daemon never comes up or the test fails.
set -u -o pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
H=/private/tmp/fsa-ui-$(openssl rand -hex 3)
LOG=$(mktemp -t ui-smoke)
SOCK="$H/Library/Application Support/FSearch/fsearch.sock"
mkdir -p "$H/root/proj"; echo x > "$H/root/proj/heronfile.txt"; echo x > "$H/root/proj/🏡 a b.txt"
HOME=$H FSEARCH_ROOT=$H/root Vendor/fsearch serve >/dev/null 2>&1 & DP=$!
cleanup() {
  kill $DP 2>/dev/null
  for _ in $(seq 10); do kill -0 $DP 2>/dev/null || break; sleep 0.5; done
  kill -9 $DP 2>/dev/null
  wait $DP 2>/dev/null
  rm -rf "$H" "$LOG"
}
trap cleanup EXIT
for _ in $(seq 50); do [ -S "$SOCK" ] && break; sleep 0.2; done
[ -S "$SOCK" ] || { echo "ui-smoke: daemon socket never appeared at $SOCK" >&2; exit 1; }
TEST_RUNNER_FSEARCH_SOCKET="$SOCK" \
  xcodebuild test -project FSearch.xcodeproj -scheme FSearch -derivedDataPath build -only-testing:AppUITests "$@" > "$LOG" 2>&1
rc=$?
grep -E 'error:|\*\* TEST' "$LOG" | cut -c1-400
exit $rc
