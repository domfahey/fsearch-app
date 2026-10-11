#!/usr/bin/env bash
# Installs the pinned Rust toolchain (RUST_TOOLCHAIN, set in ci.yml) with both
# macOS targets, using the rustup preinstalled on the runner, and makes it the
# default. No third-party action runs here.
set -euo pipefail
: "${RUST_TOOLCHAIN:?RUST_TOOLCHAIN is not set (see the env block in .github/workflows/ci.yml)}"
command -v rustup >/dev/null || { echo "setup-rust: rustup is not installed on this runner" >&2; exit 1; }
rustup toolchain install "$RUST_TOOLCHAIN" --profile minimal \
  --target aarch64-apple-darwin --target x86_64-apple-darwin
rustup default "$RUST_TOOLCHAIN"
rustc --version
