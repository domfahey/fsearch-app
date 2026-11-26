#!/bin/bash
# Builds App/Resources/Credits.html (shown in the About window) from
# THIRD_PARTY_NOTICES.md. Run after editing the notices; `--check` exits 1 if
# the committed file is out of date, or THIRD_PARTY_NOTICES.md lacks the daemon
# REV (scripts/build-daemon.sh) or a package exactVersion (project.yml).
#
# Usage: scripts/gen-credits.sh [--check]
# Prerequisites: none beyond the macOS base tools. Writes only App/Resources/Credits.html.
# Exit codes: 0 ok; 1 with --check when Credits.html differs from a fresh build or the notices are stale; 2 bad usage.
set -euo pipefail
cd "$(dirname "$0")/.."
CHECK=0
case "${1:-}" in
  "") ;;
  --check) [ $# -eq 1 ] || { echo "usage: $0 [--check]" >&2; exit 2; }; CHECK=1 ;;
  *) echo "usage: $0 [--check]" >&2; exit 2 ;;
esac
out=App/Resources/Credits.html
if [ "$CHECK" = 1 ]; then
  # The notices must name the pinned daemon commit and each pinned package version.
  stale=0
  rev=$(grep -m1 '^REV=' scripts/build-daemon.sh | grep -o '[0-9a-f]\{40\}' || true)
  [ -n "$rev" ] || { echo "gen-credits: no REV found in scripts/build-daemon.sh" >&2; exit 1; }
  grep -q "$rev" THIRD_PARTY_NOTICES.md || { echo "gen-credits: THIRD_PARTY_NOTICES.md lacks daemon REV $rev" >&2; stale=1; }
  pkgs=$(sed -n 's/^  \([A-Za-z]*\): {.*exactVersion: "\([^"]*\)".*/\1 \2/p' project.yml)
  [ -n "$pkgs" ] || { echo "gen-credits: no exactVersion packages found in project.yml" >&2; exit 1; }
  while read -r name ver; do
    grep -qF "| $name | $ver |" THIRD_PARTY_NOTICES.md || { echo "gen-credits: THIRD_PARTY_NOTICES.md lacks $name $ver" >&2; stale=1; }
  done <<< "$pkgs"
  [ "$stale" = 0 ] || exit 1
fi
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
if [ "$CHECK" = 1 ]; then
  cmp -s "$tmp" "$out" || { echo "gen-credits: $out is out of date; run scripts/gen-credits.sh" >&2; exit 1; }
else
  cp "$tmp" "$out"
fi
