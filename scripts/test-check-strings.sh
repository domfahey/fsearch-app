#!/usr/bin/env bash
# Tests scripts/check-strings.sh against valid and invalid .xcstrings fixtures.
# Uses temporary JSON fixtures only; reads/writes nothing in the repo.
# Usage: scripts/test-check-strings.sh
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHECK="$ROOT/scripts/check-strings.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

python3 -I - "$T" <<'PY' || exit 1
import copy
import json
import os
import sys

out_dir = sys.argv[1]
LOCALES = ("de", "en", "es", "fr", "ja", "ko", "pt-BR", "zh-Hans")


def unit(val="ok", state="translated"):
    return {"stringUnit": {"state": state, "value": val}}


def plural_entry(other_state="translated"):
    return {
        "variations": {
            "plural": {
                "one": unit("%lld item"),
                "other": unit("%lld items", state=other_state),
            }
        }
    }


def write_fixture(name, strings):
    path = os.path.join(out_dir, name)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump({"sourceLanguage": "en", "strings": strings}, fh, indent=2)


base = {
    "Hello": {"localizations": {loc: unit(f"Hello-{loc}") for loc in LOCALES}},
    "fsearch": {"shouldTranslate": False},
    "%lld items": {"localizations": {loc: plural_entry() for loc in LOCALES}},
}
write_fixture("1-valid.xcstrings", base)

missing_loc = copy.deepcopy(base)
del missing_loc["Hello"]["localizations"]["ko"]
write_fixture("2-missing-locale.xcstrings", missing_loc)

needs_review = copy.deepcopy(base)
needs_review["Hello"]["localizations"]["fr"] = unit("Bonjour", state="needs_review")
write_fixture("3-needs-review.xcstrings", needs_review)

empty_val = copy.deepcopy(base)
empty_val["Hello"]["localizations"]["es"] = unit("")
write_fixture("4-empty-value.xcstrings", empty_val)

stale_key = copy.deepcopy(base)
stale_key["OldKey"] = {"extractionState": "stale", "localizations": {}}
write_fixture("5-stale-key.xcstrings", stale_key)

bad_plural = copy.deepcopy(base)
bad_plural["%lld items"]["localizations"]["ja"] = plural_entry(other_state="new")
write_fixture("6-bad-plural.xcstrings", bad_plural)
PY

PASS=0
FAILN=0

run() {
  local name=$1 want=$2 fixture=$3
  "$CHECK" "$fixture" >"$T/out" 2>&1
  local rc=$?
  if { [ "$want" = 0 ] && [ "$rc" = 0 ]; } || { [ "$want" = 1 ] && [ "$rc" -ne 0 ]; }; then
    PASS=$((PASS + 1))
    echo "ok   $name"
  else
    FAILN=$((FAILN + 1))
    echo "FAIL $name (rc=$rc)"
    cat "$T/out"
  fi
}

run "valid 8-locale catalog with shouldTranslate=false and plural variations" 0 "$T/1-valid.xcstrings"
run "missing locale (7 of 8) is rejected" 1 "$T/2-missing-locale.xcstrings"
run "locale with state needs_review is rejected" 1 "$T/3-needs-review.xcstrings"
run "locale with empty value is rejected" 1 "$T/4-empty-value.xcstrings"
run "stale key is rejected" 1 "$T/5-stale-key.xcstrings"
run "plural variations entry not translated is rejected" 1 "$T/6-bad-plural.xcstrings"

echo "passed $PASS, failed $FAILN"
[ "$FAILN" = 0 ]
