#!/usr/bin/env bash
# Check that App and FSearchKit String Catalogs have no stale keys and that
# every translatable key has translated, non-empty entries for all 8 locales.
#
# Usage: scripts/check-strings.sh [catalog.xcstrings ...]
#        With no arguments, checks App/Resources/Localizable.xcstrings and
#        Packages/FSearchKit/Sources/FSearchKit/Resources/Localizable.xcstrings.
# Prerequisite: python3. Read-only: only reads .xcstrings files.
# Exit codes: 0 no problems; 1 at least one problem or invalid catalog.
set -euo pipefail

if [ "$#" -eq 0 ]; then
  cd "$(dirname "$0")/.."
  set -- \
    "App/Resources/Localizable.xcstrings" \
    "Packages/FSearchKit/Sources/FSearchKit/Resources/Localizable.xcstrings"
fi

exec python3 -I - "$@" <<'PY'
import json
import sys

LOCALES = ("de", "en", "es", "fr", "ja", "ko", "pt-BR", "zh-Hans")


def check_string_unit(path, key, loc, label, unit):
    if not isinstance(unit, dict):
        print(f"{path}: {key!r} [{loc}] {label}: invalid stringUnit")
        return 1
    probs = 0
    state = unit.get("state")
    if state != "translated":
        print(f"{path}: {key!r} [{loc}] {label}: state is {state!r}, expected 'translated'")
        probs += 1
    value = unit.get("value")
    if not isinstance(value, str) or value == "":
        print(f"{path}: {key!r} [{loc}] {label}: empty or missing value")
        probs += 1
    return probs


def check_entry_node(path, key, loc, label, node):
    if not isinstance(node, dict):
        print(f"{path}: {key!r} [{loc}] {label}: expected object")
        return 1

    has_known = False
    probs = 0

    if "stringUnit" in node:
        has_known = True
        probs += check_string_unit(path, key, loc, f"{label}.stringUnit", node["stringUnit"])

    if "variations" in node:
        has_known = True
        variations = node["variations"]
        if not isinstance(variations, dict) or not variations:
            print(f"{path}: {key!r} [{loc}] {label}.variations: expected non-empty object")
            probs += 1
        else:
            for axis, branches in variations.items():
                if not isinstance(branches, dict) or not branches:
                    print(f"{path}: {key!r} [{loc}] {label}.variations.{axis}: expected non-empty object")
                    probs += 1
                    continue
                for variant, child in branches.items():
                    probs += check_entry_node(
                        path, key, loc, f"{label}.variations.{axis}.{variant}", child
                    )

    if "substitutions" in node:
        has_known = True
        substitutions = node["substitutions"]
        if not isinstance(substitutions, dict) or not substitutions:
            print(f"{path}: {key!r} [{loc}] {label}.substitutions: expected non-empty object")
            probs += 1
        else:
            for sub_name, sub_node in substitutions.items():
                probs += check_entry_node(
                    path, key, loc, f"{label}.substitutions.{sub_name}", sub_node
                )

    if not has_known:
        print(f"{path}: {key!r} [{loc}] {label}: missing stringUnit, variations, or substitutions")
        probs += 1

    return probs


catalogs = sys.argv[1:]
translatable_keys = 0
problems = 0

for path in catalogs:
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"{path}: failed to read catalog: {exc}")
        problems += 1
        continue

    if not isinstance(data, dict) or not isinstance(data.get("strings"), dict):
        print(f"{path}: missing or invalid 'strings' object")
        problems += 1
        continue

    for key, entry in sorted(data["strings"].items()):
        if not isinstance(entry, dict):
            print(f"{path}: {key!r}: invalid key entry")
            problems += 1
            continue

        if entry.get("extractionState") == "stale":
            print(f"{path}: {key!r}: stale key (extractionState == 'stale')")
            problems += 1
            continue

        if entry.get("shouldTranslate") is False:
            continue

        translatable_keys += 1
        locs = entry.get("localizations")
        if not isinstance(locs, dict):
            print(f"{path}: {key!r}: missing 'localizations' object")
            problems += 1
            continue

        for loc in LOCALES:
            if loc not in locs:
                print(f"{path}: {key!r}: missing locale {loc}")
                problems += 1
                continue
            problems += check_entry_node(path, key, loc, loc, locs[loc])

print(f"checked {len(catalogs)} catalog(s), {translatable_keys} translatable key(s), {problems} problem(s)")
sys.exit(1 if problems else 0)
PY
