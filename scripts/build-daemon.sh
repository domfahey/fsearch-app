#!/usr/bin/env bash
# Build the pinned fsearch daemon into Vendor/fsearch, and record the revision
# in Vendor/fsearch.rev. Universal (arm64 + x86_64) by default; pass --host-only
# (or FSEARCH_HOST_ONLY=1) to compile only the current Mac's architecture.
#
# Usage: scripts/build-daemon.sh [--host-only]  (FSEARCH_REPO / FSEARCH_REV override the pin)
# Prerequisites: git, rustup and cargo, lipo (Xcode, for universal). Needs network access to clone.
#
# It builds in a temp directory and writes only to Vendor/. It never touches the
# real index (~/Library/Application Support/FSearch), LaunchAgents or ~/.local/bin.
# Exit codes: 0 on success; non-zero (from set -e) if any step fails.
set -euo pipefail
HOST_ONLY=${FSEARCH_HOST_ONLY:-0}
case "${1:-}" in
  --host-only) HOST_ONLY=1; shift ;;
  "") ;;
  *) echo "build-daemon: unknown option $1 (usage: scripts/build-daemon.sh [--host-only])" >&2; exit 2 ;;
esac
[ $# -eq 0 ] || { echo "build-daemon: unexpected arguments: $*" >&2; exit 2; }
REPO=${FSEARCH_REPO:-https://github.com/domfahey/fsearch.git}
REV=${FSEARCH_REV:-d26cf78da7a0136b0632aa7cc55d271ae7b049e7}   # domfahey/fsearch fork; bump to an upstream tag once #12-#14 merge
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
# The clone and target builds are large; remove them however the script ends.
trap 'rm -rf "$WORK"' EXIT
# Fetch exactly the pinned commit. It is reachable through the protected tag
# app-pin-2026-10-10 on the fork, so no branch is needed.
git init -q "$WORK/fsearch"
git -C "$WORK/fsearch" fetch --quiet --depth 1 "$REPO" "$REV"
git -C "$WORK/fsearch" checkout --quiet FETCH_HEAD
[ "$(git -C "$WORK/fsearch" rev-parse HEAD)" = "$REV" ] || { echo "build-daemon: fetched commit is not $REV" >&2; exit 1; }
if [ "$HOST_ONLY" = 1 ]; then
  case "$(uname -m)" in
    arm64) TARGETS=(aarch64-apple-darwin) ;;
    x86_64) TARGETS=(x86_64-apple-darwin) ;;
    *) echo "build-daemon: unsupported host arch $(uname -m)" >&2; exit 1 ;;
  esac
else
  TARGETS=(aarch64-apple-darwin x86_64-apple-darwin)
fi
# Quiet on success: the targets are usually installed already; print stderr if rustup fails.
if ! RUSTUP_OUT=$(rustup target add "${TARGETS[@]}" 2>&1); then
  printf '%s\n' "$RUSTUP_OUT" >&2
  exit 1
fi
for t in "${TARGETS[@]}"; do
  (cd "$WORK/fsearch" && cargo build --release --locked --quiet --target "$t")
done
mkdir -p "$ROOT/Vendor"
if [ "${#TARGETS[@]}" -eq 1 ]; then
  cp "$WORK/fsearch/target/${TARGETS[0]}/release/fsearch" "$ROOT/Vendor/fsearch"
else
  lipo -create -output "$ROOT/Vendor/fsearch" \
    "$WORK/fsearch/target/aarch64-apple-darwin/release/fsearch" \
    "$WORK/fsearch/target/x86_64-apple-darwin/release/fsearch"
fi
echo "$REV" > "$ROOT/Vendor/fsearch.rev"
lipo -info "$ROOT/Vendor/fsearch"
