#!/usr/bin/env bash
# Check that every relative Markdown link in the repo resolves, and that a
# #anchor points at a real heading. Skips build/, .build/, .superpowers/,
# docs/superpowers/ and Vendor/. Exits non-zero if any link is broken.
#
# Usage: scripts/check-links.sh       (run from anywhere; it changes to the repo root)
# Prerequisite: python3. Read-only: it only reads Markdown files.
# Exit codes: 0 all links resolve; 1 at least one broken link or anchor.
set -euo pipefail
cd "$(dirname "$0")/.."
# -I (isolated mode) so a stray PYTHON* variable or a module in the cwd can't change what runs.
exec python3 -I - <<'PY'
import os, re, sys
from urllib.parse import unquote

SKIP = {"build", ".build", ".superpowers", "node_modules", "Vendor", ".git", "DerivedData"}
SKIP_PATHS = {os.path.join("docs", "superpowers")}

def skipped(rel):
    return any(rel == p or rel.startswith(p + os.sep) for p in SKIP_PATHS)

files = []
for dp, dns, fns in os.walk("."):
    rel_dir = os.path.relpath(dp, ".")
    dns[:] = [d for d in dns if d not in SKIP and not skipped(os.path.normpath(os.path.join(rel_dir, d)))]
    files += [os.path.normpath(os.path.join(dp, f)) for f in fns if f.endswith(".md")]

# Drop fenced and inline code first: links in examples are not real links.
def strip_code(text):
    text = re.sub(r"^(```|~~~).*?^\1[ \t]*$", "", text, flags=re.S | re.M)
    return re.sub(r"`[^`\n]*`", "", text)

# GitHub's heading anchor: lowercase, punctuation dropped, spaces to hyphens.
def slug(h):
    h = re.sub(r"`", "", h.strip().lower())
    h = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", h)
    h = re.sub(r"[^\w\- ]", "", h, flags=re.U)
    return h.replace(" ", "-")

# Per-file cache of heading anchors; a repeated heading gets -1, -2 ... as on GitHub.
anchors = {}
def anchors_of(path):
    if path not in anchors:
        seen, out = {}, set()
        with open(path, encoding="utf-8") as fh:
            for h in re.findall(r"^#{1,6}\s+(.*?)\s*#*\s*$", strip_code(fh.read()), flags=re.M):
                s = slug(h)
                n = seen.get(s, 0)
                seen[s] = n + 1
                out.add(s if n == 0 else f"{s}-{n}")
        anchors[path] = out
    return anchors[path]

bad = 0
link = re.compile(r"(?<!!)\[[^\]]*\]\(\s*<?([^)\s>]+)>?(?:\s+\"[^\"]*\")?\s*\)|!\[[^\]]*\]\(\s*<?([^)\s>]+)")
for f in sorted(files):
    with open(f, encoding="utf-8") as fh:
        text = strip_code(fh.read())
    for m in link.finditer(text):
        target = m.group(1) or m.group(2)
        if re.match(r"^([a-z][a-z0-9+.-]*:|//)", target, re.I):
            continue
        path, _, frag = target.partition("#")
        dest = f if not path else os.path.normpath(os.path.join(os.path.dirname(f), unquote(path)))
        if not os.path.exists(dest):
            print(f"{f}: broken link: {target}"); bad += 1; continue
        if frag and dest.endswith(".md") and os.path.isfile(dest) and unquote(frag).lower() not in anchors_of(dest):
            print(f"{f}: broken anchor: {target}"); bad += 1
print(f"checked {len(files)} Markdown files, {bad} broken link(s)")
sys.exit(1 if bad else 0)
PY
