#!/usr/bin/env bash
# Installs a pinned XcodeGen release from its GitHub release zip, checking the
# zip's sha256 first, instead of `brew install` (which floats). In CI the bin
# directory is added to GITHUB_PATH; locally, add it to PATH yourself.
# Bump VERSION and SHA256 together (a release at least 2 weeks old):
#   gh api repos/yonaskolb/XcodeGen/releases --jq '.[0]|.tag_name,.published_at,(.assets[]|.name+" "+.digest)'
# Usage: scripts/install-xcodegen.sh [INSTALL_DIR]   (default: $RUNNER_TEMP/xcodegen-install or a temp dir)
set -euo pipefail
VERSION=2.46.0     # published 2026-07-16
SHA256=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806   # xcodegen.zip
DEST=${1:-${RUNNER_TEMP:-$(mktemp -d)}/xcodegen-install}
rm -rf "$DEST"; mkdir -p "$DEST"
ZIP="$DEST/xcodegen.zip"
curl --fail --silent --show-error --location --output "$ZIP" \
  "https://github.com/yonaskolb/XcodeGen/releases/download/$VERSION/xcodegen.zip"
echo "$SHA256  $ZIP" | shasum -a 256 -c - || { echo "install-xcodegen: sha256 mismatch for XcodeGen $VERSION" >&2; exit 1; }
unzip -q "$ZIP" -d "$DEST"
BIN="$DEST/xcodegen/bin"
[ -x "$BIN/xcodegen" ] || { echo "install-xcodegen: $BIN/xcodegen missing after unzip" >&2; exit 1; }
if [ -n "${GITHUB_PATH:-}" ]; then echo "$BIN" >> "$GITHUB_PATH"; fi
"$BIN/xcodegen" --version
echo "$BIN"
