#!/usr/bin/env bash
# Sync App/Resources/Localizable.xcstrings and Packages/FSearchKit's String Catalog
# from compiler-emitted .stringsdata files. Run from anywhere.
#
# Usage: scripts/sync-strings.sh
# Prerequisites: Xcode (xcrun xcstringstool, xcodebuild), xcodegen, Vendor/fsearch.
# Exit codes: 0 catalogs synced; 1 build or sync failure.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-$(xcode-select -p)}

OUT=build/loc-sync
rm -rf "$OUT"
trap 'rm -rf "$OUT"' EXIT

scripts/generate-project.sh >/dev/null
echo "== Extracting localization strings (FSearch + FSearchKit)"
xcodebuild -project FSearch.xcodeproj -scheme FSearch -configuration Debug \
  -derivedDataPath "$OUT" -destination 'platform=macOS,arch=arm64' \
  SWIFT_EMIT_LOC_STRINGS=YES CODE_SIGN_IDENTITY=- build > "$OUT.log" 2>&1 \
  || { tail -40 "$OUT.log"; rm -f "$OUT.log"; exit 1; }
rm -f "$OUT.log"

sync_catalog() {
  local catalog=$1 search_root=$2 non_translatable=$3
  local files=()
  while IFS= read -r f; do
    [ -n "$f" ] && files+=("$f")
  done < <(find "$search_root" -name '*.stringsdata' -print | sort)
  [ ${#files[@]} -gt 0 ] || { echo "sync-strings.sh: no .stringsdata files under $search_root" >&2; exit 1; }

  xcrun xcstringstool sync "$catalog" --stringsdata "${files[@]}"
  python3 -I - "$catalog" "$non_translatable" <<'PY'
import json, sys

path = sys.argv[1]
non_translatable = {s for s in sys.argv[2].split(",") if s}
with open(path, encoding="utf-8") as fh:
    data = json.load(fh)

strings = data.get("strings", {})
cleaned = {}
for key, entry in strings.items():
    if entry.get("extractionState") == "stale":
        continue
    if key in non_translatable:
        cleaned[key] = {"shouldTranslate": False}
        continue
    entry.pop("shouldTranslate", None)
    locs = entry.setdefault("localizations", {})
    en = locs.setdefault("en", {})
    unit = en.setdefault("stringUnit", {})
    if "value" not in unit:
        unit["value"] = key
    unit["state"] = "translated"
    cleaned[key] = entry

data["strings"] = cleaned
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False, sort_keys=True)
    fh.write("\n")

tr = sum(1 for v in cleaned.values() if v.get("shouldTranslate") is not False)
nt = len(cleaned) - tr
print(f"{path}: {len(cleaned)} keys ({tr} translatable, {nt} shouldTranslate=false)")
PY
}

sync_catalog \
  "App/Resources/Localizable.xcstrings" \
  "$OUT/Build/Intermediates.noindex/FSearch.build/Debug/FSearch.build/Objects-normal/arm64" \
  "fsearch"

sync_catalog \
  "Packages/FSearchKit/Sources/FSearchKit/Resources/Localizable.xcstrings" \
  "$OUT/Build/Intermediates.noindex/FSearchKit.build/Debug/FSearchKit.build/Objects-normal/arm64" \
  ""
