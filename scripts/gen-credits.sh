#!/bin/bash
# Builds App/Resources/Credits.html (shown in the About window) from
# THIRD_PARTY_NOTICES.md. Run after editing the notices; `--check` exits 1 if
# the committed file is out of date.
#
# Usage: scripts/gen-credits.sh [--check]
# Prerequisites: none beyond the macOS base tools. Writes only App/Resources/Credits.html.
# Exit codes: 0 ok; 1 with --check when Credits.html differs from a fresh build.
set -euo pipefail
cd "$(dirname "$0")/.."
out=App/Resources/Credits.html
# Build into a temp file first so --check can compare and a failure never leaves a half-written Credits.html.
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
{
  cat <<'EOF'
<!doctype html>
<html><head><meta charset="utf-8">
<style>
body { font: 11px -apple-system, sans-serif; }
pre { font: 10px ui-monospace, Menlo, monospace; white-space: pre-wrap; }
</style></head><body>
<p><b>Built on <a href="https://github.com/noahdunnagan/fsearch">fsearch</a> by Noah Dunnagan.</b>
fsearch does all of the indexing and searching; FSearch for Mac is a front end for it.
FSearch for Mac is an independent project and is not affiliated with fsearch or its author.</p>
<p>Also uses <a href="https://github.com/sindresorhus/KeyboardShortcuts">KeyboardShortcuts</a>
by Sindre Sorhus and <a href="https://sparkle-project.org">Sparkle</a>.</p>
<p>Inspired by <a href="https://www.raycast.com">Raycast</a> and <a href="https://www.voidtools.com">Everything</a> by voidtools. Not affiliated with either.</p>
<pre>
EOF
  # Escape the notices for the <pre> block (& first, so the other escapes aren't doubled).
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' THIRD_PARTY_NOTICES.md
  printf '</pre>\n</body></html>\n'
} > "$tmp"
if [ "${1:-}" = "--check" ]; then
  cmp -s "$tmp" "$out" || { echo "gen-credits: $out is out of date; run scripts/gen-credits.sh" >&2; exit 1; }
else
  cp "$tmp" "$out"
fi
