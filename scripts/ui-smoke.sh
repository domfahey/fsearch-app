#!/bin/bash
# Runs the panel UI smoke test against a throwaway daemon (temp HOME + root).
# Xcode's UI-test runner is sandboxed and cannot start the daemon itself.
set -u
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
H=/private/tmp/fsa-ui-$(openssl rand -hex 3)
mkdir -p "$H/root/proj"; echo x > "$H/root/proj/heronfile.txt"
HOME=$H FSEARCH_ROOT=$H/root Vendor/fsearch serve >/dev/null 2>&1 & DP=$!
cleanup() {
  kill $DP 2>/dev/null
  for _ in $(seq 10); do kill -0 $DP 2>/dev/null || break; sleep 0.5; done
  kill -9 $DP 2>/dev/null
  rm -rf "$H"
}
trap cleanup EXIT
sleep 3
TEST_RUNNER_FSEARCH_SOCKET="$H/Library/Application Support/FSearch/fsearch.sock" \
  xcodebuild test -project FSearch.xcodeproj -scheme FSearch -derivedDataPath build -only-testing:AppUITests > /tmp/ui-smoke.log 2>&1
grep -E 'error:|\*\* TEST' /tmp/ui-smoke.log | cut -c1-400
