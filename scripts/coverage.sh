#!/bin/bash
# Combined code coverage for the app: hosted unit tests (AppTests) plus the
# end-to-end UI tests (AppUITests via scripts/ui-smoke.sh), merged into one
# result bundle, with per-target and per-file numbers for FSearch.app.
#
#   scripts/coverage.sh                 run both suites, merge, report
#   scripts/coverage.sh --unit-only     run AppTests only
#   scripts/coverage.sh --reuse U [UI]  report on existing .xcresult bundles (no tests run)
#
# Both suites need a logged-in GUI session and nobody using the Mac: the UI
# tests synthesize keystrokes, and the unit-test host opens (unfocused) windows.
# Output goes to build/coverage/ (COVERAGE_OUT overrides).
#
# "Excluding system adapters" leaves out the functions in EXCLUDE below:
# thin pass-throughs to SMAppService, NSWorkspace/Process/Trash, app
# activation and Sparkle, which tests replace with fakes and never run for real.
set -u -o pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
OUT=${COVERAGE_OUT:-build/coverage}
mode=both
UNIT="$OUT/unit.xcresult" UI="$OUT/ui.xcresult"
case "${1:-}" in
  --unit-only) mode=unit ;;
  --reuse) mode=reuse; UNIT=${2:?--reuse needs a unit .xcresult}; UI=${3:-} ;;
  "") ;;
  *) echo "usage: $0 [--unit-only | --reuse UNIT.xcresult [UI.xcresult]]" >&2; exit 2 ;;
esac
mkdir -p "$OUT"
rc=0

if [ "$mode" != reuse ]; then
  rm -rf "$UNIT"
  echo "== AppTests (unit)"
  xcodebuild test -project FSearch.xcodeproj -scheme FSearch -derivedDataPath build \
    -only-testing:AppTests -enableCodeCoverage YES -resultBundlePath "$UNIT" > "$OUT/unit.log" 2>&1 || rc=1
  grep -E 'Test run with|error:|\*\* TEST' "$OUT/unit.log" | sort -u
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
python3 -I - "$OUT/report.json" <<'PY'
import json, re, sys
# file name -> function-name pattern of system adapters left out of the second number
EXCLUDE = {
    "SystemSeams.swift": r".",                                    # SMAppService, NSWorkspace, Process, Trash
    "Updater.swift": r"UpdateCheckState|CheckForUpdatesButton|static Updater\.start\(\)",  # Sparkle
    "Seams.swift": r"AppActivation\.activate",                    # NSApp.activate
}
d = json.load(open(sys.argv[1]))
app = next(t for t in d["targets"] if t["name"] == "FSearch.app")
cov = exe = xcov = xexe = 0
rows, excluded = [], []
for f in app["files"]:
    fc, fe = f["coveredLines"], f["executableLines"]
    pat = EXCLUDE.get(f["name"])
    ec = ee = 0
    if pat:
        for fn in f["functions"]:
            if re.search(pat, fn["name"]):
                ec += fn["coveredLines"]; ee += fn["executableLines"]
                excluded.append((f["name"], fn["name"], fn["coveredLines"], fn["executableLines"]))
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
PY
exit $rc
