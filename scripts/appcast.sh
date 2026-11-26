#!/usr/bin/env bash
# Generate or update a signed Sparkle appcast.xml with binary deltas and release
# notes extracted from CHANGELOG.md. Run from anywhere.
#
# Usage:
#   scripts/appcast.sh [options] <VERSION> <ARCHIVES_DIR>
#   scripts/appcast.sh --extract-notes <VERSION> [--changelog FILE]
#
# Options:
#   --dmg PATH                   Copy a release DMG into <ARCHIVES_DIR> as FSearch-<VERSION>.dmg first
#   --changelog FILE             Changelog file to extract notes from (default: CHANGELOG.md)
#   -o, --output FILE            Output path for appcast.xml (default: <ARCHIVES_DIR>/appcast.xml)
#   --download-url-prefix URL    Download URL prefix (default: GitHub release v<VERSION>)
#   --full-release-notes-url URL Full release notes URL (default: GitHub tag v<VERSION>)
#   --link URL                   Application homepage URL (default: GitHub repository)
#   --maximum-deltas N           Maximum binary deltas to generate (default: 5)
#   --account NAME               Keychain EdDSA account passed to generate_appcast / sign_update
#   --ed-key-file FILE           Private EdDSA key file (or '-' for stdin)
#   --skip-attestation           Local dry runs only: skip `gh attestation verify` (prints a loud warning)
#   --extract-notes VERSION      Print extracted Markdown notes for VERSION to stdout and exit
#   -h, --help                   Show this help
#
# Environment:
#   GENERATE_APPCAST             Path to Sparkle's generate_appcast binary (auto-detected under build/; never taken from PATH)
#   SIGN_UPDATE                  Path to Sparkle's sign_update binary (defaults beside generate_appcast)
#
# Before anything is signed with the EdDSA key, the DMG must pass `shasum -a 256 -c`
# against <dmg>.sha256 and `gh attestation verify <dmg> -R domfahey/fsearch-app`.
#
# Keep prior FSearch-*.dmg releases in <ARCHIVES_DIR> so Sparkle can build binary
# .delta files against them. Existing releases keep their original download URLs
# (and are re-signed with sign_update when restored). Upload the new DMG and any
# newly generated .delta files to the GitHub release, and publish only appcast.xml
# to gh-pages.
#
# Exit codes: 0 success; 1 missing tool/input, failed DMG verification or invalid CHANGELOG section; 2 bad usage.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)

usage() {
  sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'
}

fail() { echo "appcast.sh: $*" >&2; exit 1; }
bad_usage() { echo "appcast.sh: $*" >&2; usage >&2; exit 2; }

extract_notes() {
  local version=$1 changelog=$2
  [ -f "$changelog" ] || fail "changelog not found: $changelog"
  python3 -I - "$changelog" "$version" <<'PY'
import re, sys

path, version = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as fh:
    lines = fh.read().splitlines()

heading = re.compile(r"^##\s+\[" + re.escape(version) + r"\](?:\s|$)")
next_heading = re.compile(r"^##\s+\[")
ref_link = re.compile(r"^\[[^\]]+\]:\s+\S+")

start = None
for idx, line in enumerate(lines):
    if heading.match(line):
        start = idx + 1
        break

if start is None:
    print(f"appcast.sh: no section '## [{version}]' found in {path}", file=sys.stderr)
    sys.exit(1)

body = []
for line in lines[start:]:
    if next_heading.match(line):
        break
    body.append(line)

# Drop trailing blank lines and Keep-a-Changelog reference link definitions.
while body and (not body[-1].strip() or ref_link.match(body[-1])):
    body.pop()
while body and not body[0].strip():
    body.pop(0)

if not body:
    print(f"appcast.sh: section '## [{version}]' in {path} is empty", file=sys.stderr)
    sys.exit(1)

print("\n".join(body))
PY
}

# Restores original download URLs for retained older releases in appcast.xml.
# Sparkle's --download-url-prefix rewrites enclosure URLs for every archive in
# <ARCHIVES_DIR>; for GitHub Releases each version lives under its own tag URL.
# Exits 10 if appcast.xml was modified (so the caller re-signs it), 0 if unchanged.
preserve_existing_urls() {
  local prev_appcast=$1 new_appcast=$2 current_version=$3 default_repo_url=$4 use_github_default=$5
  python3 -I - "$prev_appcast" "$new_appcast" "$current_version" "$default_repo_url" "$use_github_default" <<'PY'
import os, re, sys, xml.etree.ElementTree as ET

prev_path, new_path, current_ver, repo_url, use_gh_default = sys.argv[1:6]
NS = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}

def parse_existing(path):
    """Map sparkle:version -> (main_url, {deltaFrom: url}) from an existing appcast."""
    out = {}
    if not path or not os.path.isfile(path):
        return out
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError:
        return out
    for item in root.findall("./channel/item"):
        ver_el = item.find("sparkle:version", NS)
        enc_el = item.find("enclosure")
        if ver_el is None or not (ver_el.text or "").strip() or enc_el is None:
            continue
        ver = ver_el.text.strip()
        main_url = enc_el.attrib.get("url")
        deltas = {}
        for d in item.findall("sparkle:deltas/enclosure", NS):
            df = d.attrib.get(f"{{{NS['sparkle']}}}deltaFrom")
            du = d.attrib.get("url")
            if df and du:
                deltas[df] = du
        if main_url:
            out[ver] = (main_url, deltas)
    return out

saved = parse_existing(prev_path)

with open(new_path, encoding="utf-8") as fh:
    xml_text = fh.read()

changed = False
item_re = re.compile(r"<item\b[^>]*>.*?</item>", re.S)
ver_re = re.compile(r"<sparkle:version>([^<]+)</sparkle:version>")
short_re = re.compile(r"<sparkle:shortVersionString>([^<]+)</sparkle:shortVersionString>")
enc_re = re.compile(r"<enclosure\b[^>]*>")
url_re = re.compile(r'(\burl=")([^"]*)(")')
delta_from_re = re.compile(r'\bsparkle:deltaFrom="([^"]*)"')

def replace_url(tag, new_url):
    global changed
    m = url_re.search(tag)
    if not m or m.group(2) == new_url:
        return tag
    changed = True
    return tag[:m.start(2)] + new_url + tag[m.end(2):]

def rewrite_item(match):
    block = match.group(0)
    vm = ver_re.search(block)
    sm = short_re.search(block)
    ver = vm.group(1).strip() if vm else None
    short = sm.group(1).strip() if sm else None
    if short == current_ver:
        return block

    if ver and ver in saved:
        old_main, old_deltas = saved[ver]
        def fix_enc(em):
            tag = em.group(0)
            dm = delta_from_re.search(tag)
            if dm:
                df = dm.group(1)
                return replace_url(tag, old_deltas[df]) if df in old_deltas else tag
            return replace_url(tag, old_main)
        return enc_re.sub(fix_enc, block)

    # Rebuilt from scratch without an existing appcast under default GitHub Releases layout:
    # map older release assets from v<current_ver>/ to v<short>/.
    if use_gh_default == "1" and short:
        old_prefix = f"{repo_url}/releases/download/v{current_ver}/"
        target_prefix = f"{repo_url}/releases/download/v{short}/"
        def fix_default_enc(em):
            tag = em.group(0)
            um = url_re.search(tag)
            if not um:
                return tag
            u = um.group(2)
            if u.startswith(old_prefix):
                filename = u[len(old_prefix):]
                return replace_url(tag, target_prefix + filename)
            return tag
        return enc_re.sub(fix_default_enc, block)

    return block

updated = item_re.sub(rewrite_item, xml_text)
if changed:
    with open(new_path, "w", encoding="utf-8") as fh:
        fh.write(updated)
    sys.exit(10)
PY
}

find_generate_appcast() {
  if [ -n "${GENERATE_APPCAST:-}" ]; then
    [ -x "$GENERATE_APPCAST" ] || fail "GENERATE_APPCAST is not executable: $GENERATE_APPCAST"
    printf '%s\n' "$GENERATE_APPCAST"
    return
  fi
  local candidate
  for candidate in \
    "$REPO_ROOT/build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" \
    "$REPO_ROOT/build/release-derived/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
  do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return
    fi
  done
  # No PATH fallback: a tool earlier on PATH would receive the EdDSA key.
  fail "Sparkle's generate_appcast not found (run 'make build' first, or set GENERATE_APPCAST)"
}

find_sign_update() {
  local gen_bin=$1
  if [ -n "${SIGN_UPDATE:-}" ]; then
    [ -x "$SIGN_UPDATE" ] || fail "SIGN_UPDATE is not executable: $SIGN_UPDATE"
    printf '%s\n' "$SIGN_UPDATE"
    return
  fi
  local sibling
  sibling="$(dirname "$gen_bin")/sign_update"
  if [ -x "$sibling" ]; then
    printf '%s\n' "$sibling"
    return
  fi
  fail "Sparkle's sign_update not found beside $gen_bin (set SIGN_UPDATE)"
}

DMG_SRC=""
CHANGELOG="$REPO_ROOT/CHANGELOG.md"
OUTPUT=""
DOWNLOAD_PREFIX=""
FULL_NOTES_URL=""
LINK_URL="https://github.com/domfahey/fsearch-app"
MAX_DELTAS="5"
ACCOUNT=""
ED_KEY_FILE=""
EXTRACT_ONLY=""
SKIP_ATTEST=0
POSITIONAL=()

while [ $# -gt 0 ]; do
  case "$1" in
    --dmg) [ $# -ge 2 ] || bad_usage "--dmg needs a path"; DMG_SRC=$2; shift 2 ;;
    --changelog) [ $# -ge 2 ] || bad_usage "--changelog needs a path"; CHANGELOG=$2; shift 2 ;;
    -o|--output) [ $# -ge 2 ] || bad_usage "$1 needs a path"; OUTPUT=$2; shift 2 ;;
    --download-url-prefix) [ $# -ge 2 ] || bad_usage "--download-url-prefix needs a URL"; DOWNLOAD_PREFIX=$2; shift 2 ;;
    --full-release-notes-url) [ $# -ge 2 ] || bad_usage "--full-release-notes-url needs a URL"; FULL_NOTES_URL=$2; shift 2 ;;
    --link) [ $# -ge 2 ] || bad_usage "--link needs a URL"; LINK_URL=$2; shift 2 ;;
    --maximum-deltas) [ $# -ge 2 ] || bad_usage "--maximum-deltas needs a number"; MAX_DELTAS=$2; shift 2 ;;
    --account) [ $# -ge 2 ] || bad_usage "--account needs a name"; ACCOUNT=$2; shift 2 ;;
    --ed-key-file) [ $# -ge 2 ] || bad_usage "--ed-key-file needs a path"; ED_KEY_FILE=$2; shift 2 ;;
    --skip-attestation) SKIP_ATTEST=1; shift ;;
    --extract-notes) [ $# -ge 2 ] || bad_usage "--extract-notes needs a version"; EXTRACT_ONLY=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; POSITIONAL+=("$@"); break ;;
    -*) bad_usage "unknown option: $1" ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done

if [ -n "$EXTRACT_ONLY" ]; then
  [ ${#POSITIONAL[@]} -eq 0 ] || bad_usage "unexpected arguments with --extract-notes"
  extract_notes "${EXTRACT_ONLY#v}" "$CHANGELOG"
  exit 0
fi

[ ${#POSITIONAL[@]} -eq 2 ] || bad_usage "expected <VERSION> <ARCHIVES_DIR>"
VERSION=${POSITIONAL[0]#v}
ARCHIVES_DIR=${POSITIONAL[1]}

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]] \
  || bad_usage "invalid version: '$VERSION'"
[[ "$MAX_DELTAS" =~ ^[0-9]+$ ]] \
  || bad_usage "--maximum-deltas must be a non-negative integer (got '$MAX_DELTAS')"

# The DMG about to be signed must match its published checksum and carry a build
# provenance attestation from this repo's CI.
verify_dmg() {
  local dmg=$1
  [ -f "$dmg.sha256" ] || fail "missing checksum $dmg.sha256 (refusing to sign an unverified DMG)"
  # Compare hashes directly: `shasum -c` would check whatever file the .sha256 names, not $dmg.
  local want got
  want=$(/usr/bin/awk 'NR==1{print tolower($1)}' "$dmg.sha256")
  got=$(/usr/bin/shasum -a 256 "$dmg" | /usr/bin/awk '{print $1}')
  [[ "$want" =~ ^[0-9a-f]{64}$ ]] || fail "no SHA-256 in $dmg.sha256"
  [ "$got" = "$want" ] || fail "checksum mismatch for $dmg"
  if [ "$SKIP_ATTEST" = 1 ]; then
    echo "appcast.sh: WARNING: --skip-attestation: NOT verifying build provenance of $dmg. Never use this for a real release." >&2
  else
    command -v gh >/dev/null 2>&1 || fail "gh not found; cannot verify attestation (or pass --skip-attestation for a local dry run)"
    gh attestation verify "$dmg" -R domfahey/fsearch-app >/dev/null \
      || fail "gh attestation verify failed for $dmg"
  fi
}

mkdir -p "$ARCHIVES_DIR"
TARGET_DMG="$ARCHIVES_DIR/FSearch-$VERSION.dmg"
if [ -n "$DMG_SRC" ]; then
  [ -f "$DMG_SRC" ] || fail "DMG not found: $DMG_SRC"
  verify_dmg "$DMG_SRC"
  if [ ! "$DMG_SRC" -ef "$TARGET_DMG" ]; then
    cp -f "$DMG_SRC" "$TARGET_DMG"
  fi
fi
[ -f "$TARGET_DMG" ] || fail "expected DMG at $TARGET_DMG (pass --dmg PATH or copy it there first)"
[ -n "$DMG_SRC" ] || verify_dmg "$TARGET_DMG"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

NOTES_FILE="$ARCHIVES_DIR/FSearch-$VERSION.md"
NOTES_TMP="$TMP_DIR/notes.md"
extract_notes "$VERSION" "$CHANGELOG" > "$NOTES_TMP"
mv "$NOTES_TMP" "$NOTES_FILE"

GEN=$(find_generate_appcast)
USE_GITHUB_DEFAULT=0
if [ -z "$DOWNLOAD_PREFIX" ]; then
  USE_GITHUB_DEFAULT=1
  DOWNLOAD_PREFIX="https://github.com/domfahey/fsearch-app/releases/download/v$VERSION/"
fi
[ -n "$FULL_NOTES_URL" ] || FULL_NOTES_URL="https://github.com/domfahey/fsearch-app/releases/tag/v$VERSION"
[ -n "$OUTPUT" ] || OUTPUT="$ARCHIVES_DIR/appcast.xml"

# Snapshot any existing appcast before generate_appcast runs so retained older
# releases keep their original per-version asset URLs.
PREV_APPCAST=""
if [ -f "$OUTPUT" ]; then
  PREV_APPCAST="$TMP_DIR/prev-appcast.xml"
  cp "$OUTPUT" "$PREV_APPCAST"
fi

# If reading the EdDSA key from stdin ('-'), buffer it once into a 0600 temp file
# so both generate_appcast and sign_update can read it.
KEY_FILE_ARG="$ED_KEY_FILE"
if [ "$ED_KEY_FILE" = "-" ]; then
  KEY_FILE_ARG="$TMP_DIR/eddsa.key"
  ( umask 077; cat > "$KEY_FILE_ARG" )
fi

ARGS=(
  --download-url-prefix "$DOWNLOAD_PREFIX"
  --embed-release-notes
  --full-release-notes-url "$FULL_NOTES_URL"
  --link "$LINK_URL"
  --maximum-deltas "$MAX_DELTAS"
  -o "$OUTPUT"
)
[ -n "$ACCOUNT" ] && ARGS+=(--account "$ACCOUNT")
[ -n "$KEY_FILE_ARG" ] && ARGS+=(--ed-key-file "$KEY_FILE_ARG")

echo "Generating appcast for FSearch $VERSION -> $OUTPUT"
"$GEN" "${ARGS[@]}" "$ARCHIVES_DIR"

RESTORE_RC=0
preserve_existing_urls "$PREV_APPCAST" "$OUTPUT" "$VERSION" "https://github.com/domfahey/fsearch-app" "$USE_GITHUB_DEFAULT" || RESTORE_RC=$?
if [ "$RESTORE_RC" -eq 10 ]; then
  SIGN=$(find_sign_update "$GEN")
  SIGN_ARGS=()
  [ -n "$ACCOUNT" ] && SIGN_ARGS+=(--account "$ACCOUNT")
  [ -n "$KEY_FILE_ARG" ] && SIGN_ARGS+=(--ed-key-file "$KEY_FILE_ARG")
  "$SIGN" ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} "$OUTPUT"
elif [ "$RESTORE_RC" -ne 0 ]; then
  fail "failed to preserve existing release URLs in $OUTPUT"
fi

DELTAS=()
while IFS= read -r d; do
  [ -n "$d" ] && DELTAS+=("$d")
done < <(find "$ARCHIVES_DIR" -maxdepth 1 -name '*.delta' -print | sort)

echo "Wrote signed appcast: $OUTPUT"
echo "Release notes file:   $NOTES_FILE"
if [ ${#DELTAS[@]} -gt 0 ]; then
  echo "Delta files to attach to GitHub release v$VERSION:"
  for d in "${DELTAS[@]}"; do
    echo "  $d"
  done
fi
echo "Next: attach FSearch-$VERSION.dmg (and any .delta files above) to release v$VERSION, then publish only $OUTPUT to gh-pages."
