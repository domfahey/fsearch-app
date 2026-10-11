#!/bin/bash
# Combined code coverage for the app: hosted unit tests (AppTests) plus the
# end-to-end UI tests (AppUITests via scripts/ui-smoke.sh), merged into one
# result bundle, with per-target and per-file numbers for FSearch.app.
#
#   scripts/coverage.sh                 run both suites, merge, report
#   scripts/coverage.sh --unit-only     run AppTests only
#   scripts/coverage.sh --reuse U [UI]  report on existing .xcresult bundles (no tests run)
#   scripts/coverage.sh --kit-only      FSearchKit package coverage only (swift test, no app host)
#   --min PERCENT (or COVERAGE_MIN)     exit non-zero if FSearchKit line coverage, or FSearch.app
#                                       coverage excluding system adapters, is below PERCENT.
#                                       Combines with any mode. The FSearchKit gate runs with
#                                       --kit-only and in the default (both suites) mode, not with
#                                       --unit-only (CI's kit job gates FSearchKit already) or --reuse.
#
# The UI tests need a logged-in GUI session and nobody using the Mac, since they
# synthesize keystrokes. The unit-test host is inert: no window becomes key or visible.
# Output goes to build/coverage/ (COVERAGE_OUT overrides).
#
# "Excluding system adapters" leaves out the functions in EXCLUDE below:
# thin pass-throughs to SMAppService, NSWorkspace/Process/Trash, app
# activation and Sparkle, which tests replace with fakes and never run for real.
#
# Prerequisites: Xcode, and `xcodegen generate` run once (FSearch.xcodeproj);
# the daemon at Vendor/fsearch for the UI tests. It never launches the app outside
# those test runs and never touches the real index or the user's real defaults.
# Exit codes: 0 ok; 1 a test failed, a gate was missed or a report couldn't be
# built; 2 bad usage or a malformed --min.
#
# No `set -e`: both suites should run and be reported even if the first fails, so
# failures are collected in $rc. `-u -o pipefail` still catch typos and broken pipes.
set -u -o pipefail
cd "$(dirname "$0")/.." || exit 1
export DEVELOPER_DIR=${DEVELOPER_DIR:-$(xcode-select -p)}
OUT=${COVERAGE_OUT:-build/coverage}
mode=both
UNIT="$OUT/unit.xcresult" UI="$OUT/ui.xcresult"
MIN=${COVERAGE_MIN:-}
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --min) MIN=${2:?--min needs a percentage}; shift 2 ;;
    --min=*) MIN=${1#--min=}; shift ;;
    *) args+=("$1"); shift ;;
  esac
done
# --min must be a plain decimal number (no sign, one dot at most).
case "$MIN" in "" | *[!0-9.]* | *.*.*) [ -z "$MIN" ] || { echo "coverage: --min must be a number, got '$MIN'" >&2; exit 2; } ;; esac
# Re-set the positional parameters to what remains after removing --min; ${args[@]+...} is safe when empty under `set -u`.
set -- ${args[@]+"${args[@]}"}
usage() { echo "usage: $0 [--unit-only | --kit-only | --reuse UNIT.xcresult [UI.xcresult]] [--min PERCENT]" >&2; exit 2; }
case "${1:-}" in
  --unit-only) mode=unit ;;
  --kit-only) mode=kit ;;
  --reuse) mode=reuse; UNIT=${2:?--reuse needs a unit .xcresult}; UI=${3:-} ;;
  "") ;;
  *) usage ;;
esac
mkdir -p "$OUT"
rc=0
# Throwaway defaults suites the tests leave behind (TestEnv, AppDefaults.testSuiteName);
# never the real com.domfahey.fsearch.plist.
# Only the apptests suites; the glob can't match com.domfahey.fsearch.plist.
sweep_test_defaults() { rm -f "$HOME"/Library/Preferences/com.domfahey.fsearch.apptests.*.plist; }
trap sweep_test_defaults EXIT

# FSearchKit line coverage from SwiftPM (llvm-cov), gated by --min.
kit_coverage() {
  echo "== FSearchKit (swift test --enable-code-coverage)"
  ( cd Packages/FSearchKit && swift test --enable-code-coverage > "../../$OUT/kit.log" 2>&1 ) || { tail -20 "$OUT/kit.log"; echo "coverage: FSearchKit tests failed" >&2; return 1; }
  local pkg=Packages/FSearchKit bin prof
  bin=$(find "$pkg/.build" -name FSearchKitPackageTests.xctest -path '*debug*' | head -1)
  prof=$pkg/.build/debug/codecov/default.profdata
  [ -n "$bin" ] && [ -f "$prof" ] || { echo "coverage: FSearchKit coverage data not found" >&2; return 1; }
  xcrun llvm-cov export -summary-only "$bin/Contents/MacOS/FSearchKitPackageTests" -instr-profile="$prof" \
    -ignore-filename-regex='Tests/|\.build/' > "$OUT/kit.json" || return 1
  python3 -I - "$OUT/kit.json" "$MIN" <<'PY'
import json, sys
t = json.load(open(sys.argv[1]))["data"][0]["totals"]["lines"]
pct = t["percent"]
print(f"FSearchKit lines: {pct:.2f}% ({t['covered']}/{t['count']})")
if sys.argv[2] and pct < float(sys.argv[2]):
    print(f"coverage: FSearchKit {pct:.2f}% is below the minimum {sys.argv[2]}%", file=sys.stderr)
    sys.exit(1)
PY
}

if [ "$mode" = kit ]; then kit_coverage; exit $?; fi
if [ "$mode" = both ] && [ -n "$MIN" ]; then kit_coverage || rc=1; fi

if [ "$mode" != reuse ]; then
  rm -rf "$UNIT"
  echo "== AppTests (unit)"
  # In CI the packages must come from the committed Package.resolved (scripts/generate-project.sh).
  xcodebuild test -project FSearch.xcodeproj -scheme FSearch -derivedDataPath build \
    ${CI:+-onlyUsePackageVersionsFromResolvedFile} \
    -only-testing:AppTests -enableCodeCoverage YES -resultBundlePath "$UNIT" > "$OUT/unit.log" 2>&1 || rc=1
  grep -E 'Test run with|error:|\*\* TEST|✘|recorded an issue' "$OUT/unit.log" | sort -u
  if [ "$mode" = both ]; then
    rm -rf "$UI"
    echo "== AppUITests (end to end)"
    bash scripts/ui-smoke.sh -enableCodeCoverage YES -resultBundlePath "$PWD/$UI" || rc=1
  else
    UI=
  fi
fi

BUNDLES=()
for b in "$UNIT" "$UI"; do [ -n "$b" ] && [ -d "$b" ] && BUNDLES+=("$b"); done
[ ${#BUNDLES[@]} -gt 0 ] || { echo "coverage: no result bundles" >&2; exit 1; }
if [ ${#BUNDLES[@]} -gt 1 ]; then
  REPORT="$OUT/merged.xcresult"
  rm -rf "$REPORT"
  xcrun xcresulttool merge "${BUNDLES[@]}" --output-path "$REPORT" >/dev/null || { echo "coverage: merge failed" >&2; exit 1; }
else
  REPORT=${BUNDLES[0]}
fi

for b in "${BUNDLES[@]}"; do
  echo "== $(basename "$b")"
  xcrun xccov view --report --only-targets "$b" | grep -E 'FSearch.app|FSearchKit|Name'
done
echo "== combined ($(basename "$REPORT"))"
xcrun xccov view --report --only-targets "$REPORT"

xcrun xccov view --report --json "$REPORT" > "$OUT/report.json"
python3 -I - "$OUT/report.json" "$MIN" <<'PY' || rc=1
import json, re, sys
# file name -> the functions (exact xccov names) of system adapters left out
# of the second number. Listed one by one, so a new function in these files is
# counted unless someone decides it is an adapter too.
# SMAppService members shared by the helper and login-item adapters.
_SM = ["service.getter", "status.getter", "register()", "unregister()", "openSystemSettingsLoginItems()"]
EXCLUDE = {
    "SystemSeams.swift": [f"{c}.{f}" for c in ("SMAppHelperService", "SMAppLoginItemService") for f in _SM] + [
        "SystemWorkspace.ws.getter", "SystemWorkspace.open(_:)",
        "SystemWorkspace.open(_:withApplicationAt:completion:)",
        "closure #1 in SystemWorkspace.open(_:withApplicationAt:completion:)",
        "SystemWorkspace.activateFileViewerSelecting(_:)",
        "SystemWorkspace.urlForApplication(withBundleIdentifier:)",
        "SystemWorkspace.urlsForApplications(toOpen:)",
        "SystemWorkspace.trash(_:)",
    ],
    "Updater.swift": [                                            # Sparkle
        "static Updater.start()", "variable initialization expression of UpdateCheckState._canCheck",
        "UpdateCheckState.init(updater:)", "CheckForUpdatesButton.init(controller:)",
        "implicit closure #1 in CheckForUpdatesButton.init(controller:)",
        "CheckForUpdatesButton.body.getter", "closure #1 in CheckForUpdatesButton.body.getter",
    ],
    "Seams.swift": [                                              # NSApp.activate
        "closure #1 in default argument 1 of static AppActivation.live(inert:activate:)",
    ],
}
# A renamed or removed excluded function is reported as a problem, so the list can't silently go stale.
d = json.load(open(sys.argv[1]))
app = next(t for t in d["targets"] if t["name"] == "FSearch.app")
cov = exe = xcov = xexe = 0
rows, excluded, problems = [], [], []
for f in app["files"]:
    fc, fe = f["coveredLines"], f["executableLines"]
    names = EXCLUDE.get(f["name"], [])
    ec = ee = 0
    found = set()
    for fn in f["functions"]:
        if fn["name"] in names:
            found.add(fn["name"])
            ec += fn["coveredLines"]; ee += fn["executableLines"]
            excluded.append((f["name"], fn["name"], fn["coveredLines"], fn["executableLines"]))
    for missing in sorted(set(names) - found):
        problems.append(f"{f['name']}: excluded function not in the report (renamed?): {missing}")
    if ee > fe or ec > fc:
        problems.append(f"{f['name']}: excludes {ee} lines of {fe} executable")
    cov += fc; exe += fe; xcov += fc - ec; xexe += fe - ee
    rows.append((f["name"], fc, fe))
print("\n== FSearch.app per file")
for name, c, e in sorted(rows, key=lambda r: r[1] / max(r[2], 1)):
    print(f"  {100 * c / max(e, 1):6.2f}%  {c:4d}/{e:<4d}  {name}")
print("\n== excluded system adapters (covered/executable lines)")
for fname, fn, c, e in excluded:
    print(f"  {c:3d}/{e:<3d}  {fname}: {fn}")
print(f"\nFSearch.app raw:                        {100 * cov / exe:.2f}% ({cov}/{exe})")
print(f"FSearch.app excluding system adapters:  {100 * xcov / xexe:.2f}% ({xcov}/{xexe})")
for p in problems: print(f"coverage: {p}", file=sys.stderr)
bad = bool(problems)
if len(sys.argv) > 2 and sys.argv[2] and 100 * xcov / xexe < float(sys.argv[2]):
    print(f"coverage: FSearch.app excluding system adapters {100 * xcov / xexe:.2f}% is below the minimum {sys.argv[2]}%", file=sys.stderr)
    bad = True
sys.exit(1 if bad else 0)
PY
exit $rc
