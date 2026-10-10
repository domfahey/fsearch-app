#!/usr/bin/env bash
# Build the pinned fsearch daemon as a universal binary into Vendor/fsearch.
set -euo pipefail
REPO=${FSEARCH_REPO:-https://github.com/domfahey/fsearch.git}
REV=${FSEARCH_REV:-d26cf78}   # bump to an upstream tag once #12-#14 merge
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
git clone --quiet "$REPO" "$WORK/fsearch"
git -C "$WORK/fsearch" checkout --quiet "$REV"
rustup target add aarch64-apple-darwin x86_64-apple-darwin >/dev/null
for t in aarch64-apple-darwin x86_64-apple-darwin; do
  (cd "$WORK/fsearch" && cargo build --release --quiet --target "$t")
done
mkdir -p "$ROOT/Vendor"
lipo -create -output "$ROOT/Vendor/fsearch" \
  "$WORK/fsearch/target/aarch64-apple-darwin/release/fsearch" \
  "$WORK/fsearch/target/x86_64-apple-darwin/release/fsearch"
echo "$REV" > "$ROOT/Vendor/fsearch.rev"
lipo -info "$ROOT/Vendor/fsearch"
