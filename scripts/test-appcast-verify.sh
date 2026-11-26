#!/usr/bin/env bash
# Checks that appcast.sh refuses to sign an unverified DMG and ignores generate_appcast on PATH.
# Uses a fake DMG and stub tools; signs nothing. Usage: scripts/test-appcast-verify.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/dl" "$T/arch"
printf 'fake dmg' > "$T/dl/FSearch-1.2.3.dmg"
printf '## [1.2.3]\n- x\n' > "$T/CHANGELOG.md"
printf '#!/bin/sh\necho ran >> "%s/signed"\nwhile [ $# -gt 1 ]; do [ "$1" = -o ] && echo "<rss/>" > "$2"; shift; done\n' "$T" > "$T/bin/gen"; chmod +x "$T/bin/gen"
printf '#!/bin/sh\n[ -z "$GH_FAIL" ]\n' > "$T/bin/gh"; chmod +x "$T/bin/gh"
cp "$T/bin/gen" "$T/bin/generate_appcast"
PASS=0; FAILN=0
run() { # name expect(0|1) [VAR=val...] cmd...
  local name=$1 want=$2; shift 2
  rm -f "$T/signed"
  env PATH="$T/bin:$PATH" GENERATE_APPCAST="$T/bin/gen" "$@" >"$T/out" 2>&1; local rc=$?
  if { [ "$want" = 0 ] && [ $rc = 0 ] && [ -f "$T/signed" ]; } || { [ "$want" = 1 ] && [ $rc != 0 ] && [ ! -f "$T/signed" ]; }; then
    PASS=$((PASS+1)); echo "ok   $name"
  else FAILN=$((FAILN+1)); echo "FAIL $name (rc=$rc)"; cat "$T/out"; fi
}
A=("$ROOT/scripts/appcast.sh" --changelog "$T/CHANGELOG.md" --dmg "$T/dl/FSearch-1.2.3.dmg")
run "no .sha256 is refused" 1 "${A[@]}" 1.2.3 "$T/arch"
(cd "$T/dl" && shasum -a 256 FSearch-1.2.3.dmg > FSearch-1.2.3.dmg.sha256)
run "good checksum and attestation signs" 0 "${A[@]}" 1.2.3 "$T/arch"
run "failed attestation is refused" 1 GH_FAIL=1 "${A[@]}" 1.2.3 "$T/arch"
run "--skip-attestation signs with a warning" 0 GH_FAIL=1 "${A[@]}" --skip-attestation 1.2.3 "$T/arch"
grep -q WARNING "$T/out" || { FAILN=$((FAILN+1)); echo "FAIL no warning printed"; }
# The .sha256 must hash this DMG, whatever file name is written inside it.
cp "$T/dl/FSearch-1.2.3.dmg" "$T/dl/renamed.dmg"; cp "$T/dl/FSearch-1.2.3.dmg.sha256" "$T/dl/renamed.dmg.sha256"
run "renamed DMG with a matching hash signs" 0 "$ROOT/scripts/appcast.sh" --changelog "$T/CHANGELOG.md" --dmg "$T/dl/renamed.dmg" 1.2.3 "$T/arch"
printf 'other' > "$T/dl/other.dmg"; cp "$T/dl/FSearch-1.2.3.dmg.sha256" "$T/dl/other.dmg.sha256"
run ".sha256 naming a sibling file is refused" 1 "$ROOT/scripts/appcast.sh" --changelog "$T/CHANGELOG.md" --dmg "$T/dl/other.dmg" 1.2.3 "$T/arch"
printf 'tampered' > "$T/dl/FSearch-1.2.3.dmg"
run "checksum mismatch is refused" 1 "${A[@]}" 1.2.3 "$T/arch"
# generate_appcast on PATH must not be used (no GENERATE_APPCAST, none under build/).
if [ ! -e "$ROOT/build/SourcePackages" ] && [ ! -e "$ROOT/build/release-derived/SourcePackages" ]; then
  (cd "$T/dl" && shasum -a 256 FSearch-1.2.3.dmg > FSearch-1.2.3.dmg.sha256)
  rm -f "$T/signed"
  env -u GENERATE_APPCAST PATH="$T/bin:$PATH" "${A[@]}" 1.2.3 "$T/arch" >"$T/out" 2>&1; rc=$?
  if [ $rc != 0 ] && [ ! -f "$T/signed" ]; then PASS=$((PASS+1)); echo "ok   PATH generate_appcast ignored"
  else FAILN=$((FAILN+1)); echo "FAIL PATH generate_appcast was used"; fi
fi
echo "passed $PASS, failed $FAILN"; [ "$FAILN" = 0 ]
