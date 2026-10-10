#!/usr/bin/env bash
# Generates FSearch.xcodeproj with XcodeGen and seeds it with the committed
# Package.resolved, so the Swift packages resolve to the reviewed revisions.
# Build with -onlyUsePackageVersionsFromResolvedFile (CI and release.sh do).
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
DIR=FSearch.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
mkdir -p "$DIR"
cp Package.resolved "$DIR/Package.resolved"
