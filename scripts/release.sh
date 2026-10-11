#!/usr/bin/env bash
# Build, sign, notarize and package a release DMG. Run from anywhere.
# Usage: scripts/release.sh [--prepare | --sign] [VERSION]
#   (VERSION defaults to the exact tag at HEAD, minus a leading "v")
#   no flag     both phases, one after the other (the local release)
#   --prepare   build only: the daemon, the Xcode project, the Swift packages and an
#               ad-hoc signed archive in build/release/. Needs no signing identity.
#   --sign      sign, notarize and package the archive --prepare left for this
#               commit and version. Builds and fetches nothing.
# CI runs --prepare before it imports the Developer ID keychain and --sign after, so
# no third-party build script, package manifest or download runs while the key is unlocked.
# CFBundleShortVersionString = VERSION; CFBundleVersion = `git rev-list --count HEAD`
# (needs full history), which must exceed the last released build: the one recorded in
# $LAST_BUILD_FILE (default release/last-build; written after a successful run) and the
# highest v[0-9]* tag other than v$VERSION on HEAD (`git rev-list --count <tag>`), whichever is higher.
# Prerequisites (checked up front): DEVELOPER_ID, a notarytool profile, a real Sparkle key.
# Also needs Xcode, xcodegen, Rust (for build-daemon.sh) and a full git clone with its tags.
# Environment: FSEARCH_PREBUILT=1 uses Vendor/fsearch as built; FSEARCH_PROJECT_READY=1
# uses FSearch.xcodeproj and the packages already resolved into $RELEASE_DERIVED_DATA
# (default build/release-derived) instead of generating and resolving them again.
#
# Writes only under build/ and release/last-build. It never touches the
# real index, ~/Library/Application Support/FSearch, LaunchAgents or ~/.local/bin.
# Exit codes: 0 released (or prepared); 1 any failed check or step (the message says which).
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE=${NOTARY_PROFILE:-fsearch-notary}
ENTITLEMENTS=App/Resources/FSearch.entitlements
# CI stores the notary profile in a temporary keychain and exports KEYCHAIN.
NOTARY_KC=()
[ -n "${KEYCHAIN:-}" ] && NOTARY_KC=(--keychain "$KEYCHAIN")
DERIVED=${RELEASE_DERIVED_DATA:-build/release-derived}
fail() { echo "release.sh: $*" >&2; exit 1; }

PHASE=all
case "${1:-}" in
  --prepare) PHASE=prepare; shift ;;
  --sign) PHASE=sign; shift ;;
  -*) fail "unknown option $1 (usage: scripts/release.sh [--prepare | --sign] [VERSION])" ;;
esac

# The signing prerequisites; --prepare needs none of them.
if [ "$PHASE" != prepare ]; then
  [ -n "${DEVELOPER_ID:-}" ] || fail "DEVELOPER_ID is not set (e.g. 'Developer ID Application: Your Name (TEAMID)')"
  # Capture first: `... | grep -q` can SIGPIPE the producer and fail under pipefail.
  IDENTITIES=$(security find-identity -v -p codesigning)
  grep -qF "$DEVELOPER_ID" <<<"$IDENTITIES" \
    || fail "no codesigning identity matching '$DEVELOPER_ID' in the keychain"
  xcrun notarytool history --keychain-profile "$PROFILE" ${NOTARY_KC[@]+"${NOTARY_KC[@]}"} >/dev/null 2>&1 \
    || fail "notarytool profile '$PROFILE' not found (xcrun notarytool store-credentials $PROFILE)"
fi
KEY=$(/usr/libexec/PlistBuddy -c "Print SUPublicEDKey" App/Resources/Info.plist)
{ [ -n "$KEY" ] && [ "$KEY" != "REPLACE_WITH_SPARKLE_PUBLIC_KEY" ]; } \
  || fail "SUPublicEDKey in App/Resources/Info.plist is still the placeholder (see docs/release-checklist.md)"

VERSION=${1:-$(git describe --tags --exact-match 2>/dev/null || true)}
VERSION=${VERSION#v}
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?$ ]] \
  || fail "no valid version: pass one (scripts/release.sh 0.1.0) or run on a tagged commit (got '${VERSION}')"
[ "$(git rev-parse --is-shallow-repository)" = false ] \
  || fail "shallow clone: CFBundleVersion needs full history (git fetch --unshallow)"
BUILD=$(git rev-list --count HEAD)
# The last released build: the higher of the local record and the previous version tag.
LAST_BUILD_FILE=${LAST_BUILD_FILE:-release/last-build}
LAST=0; LAST_FROM=""
if [ -f "$LAST_BUILD_FILE" ]; then
  LAST=$(tr -d '[:space:]' < "$LAST_BUILD_FILE")
  [[ "$LAST" =~ ^[0-9]+$ ]] || fail "$LAST_BUILD_FILE does not hold a build number"
  LAST_FROM=$LAST_BUILD_FILE
fi
# A fresh CI checkout has no release/ folder, so the tags are its record: every v[0-9]*
# tag except this release's own (v$VERSION on HEAD) is an earlier release, built as
# `git rev-list --count <tag>`. Another tag on HEAD is a release of this same build,
# so re-tagging a released commit fails the check below.
TAGS=$(git tag --list 'v[0-9]*')
if [ "${GITHUB_ACTIONS:-}" = true ] && [ -z "$TAGS" ]; then
  fail "no v[0-9]* tags in this checkout; fetch them (actions/checkout fetch-depth: 0, fetch-tags: true)"
fi
HEAD_SHA=$(git rev-parse HEAD)
while IFS= read -r t; do
  [ -n "$t" ] || continue
  TAG_SHA=$(git rev-parse "$t^{commit}")
  [ "$t" = "v$VERSION" ] && [ "$TAG_SHA" = "$HEAD_SHA" ] && continue
  TAG_BUILD=$(git rev-list --count "$t^{commit}")
  if [ "$TAG_BUILD" -gt "$LAST" ]; then LAST=$TAG_BUILD; LAST_FROM="tag $t"; fi
done <<<"$TAGS"
if [ -n "$LAST_FROM" ]; then
  [ "$BUILD" -gt "$LAST" ] \
    || fail "CFBundleVersion $BUILD is not greater than the last release's $LAST ($LAST_FROM); Sparkle would not offer it"
  echo "Last released build: $LAST ($LAST_FROM)"
else
  echo "No previous release found ($LAST_BUILD_FILE absent, no other v[0-9]* tag): skipping the build-number check"
fi
echo "Releasing $VERSION (build $BUILD), phase: $PHASE"
OUT=build/release
APP="$OUT/FSearch.xcarchive/Products/Applications/FSearch.app"
# What --prepare built, so --sign signs only an archive of this commit and version.
STAMP="$VERSION $BUILD $(git rev-parse HEAD)"

if [ "$PHASE" != sign ]; then
  rm -rf "$OUT"; mkdir -p "$OUT"
  # CI builds the daemon before it imports the signing keychain and sets FSEARCH_PREBUILT=1,
  # so third-party build scripts never run while the Developer ID key is unlocked.
  if [ "${FSEARCH_PREBUILT:-}" = 1 ]; then
    [ -x Vendor/fsearch ] || fail "FSEARCH_PREBUILT=1 but Vendor/fsearch is missing (run scripts/build-daemon.sh first)"
  else
    scripts/build-daemon.sh
  fi
  # CI generates the project and resolves the packages in steps of their own and sets
  # FSEARCH_PROJECT_READY=1; the archive below then fetches nothing new.
  if [ "${FSEARCH_PROJECT_READY:-}" = 1 ]; then
    [ -d FSearch.xcodeproj ] || fail "FSEARCH_PROJECT_READY=1 but FSearch.xcodeproj is missing (run scripts/generate-project.sh first)"
    [ -d "$DERIVED/SourcePackages" ] \
      || fail "FSEARCH_PROJECT_READY=1 but $DERIVED/SourcePackages is missing (resolve the packages into $DERIVED first)"
  else
    scripts/generate-project.sh
    xcodebuild -resolvePackageDependencies -project FSearch.xcodeproj -scheme FSearch \
      -derivedDataPath "$DERIVED" -onlyUsePackageVersionsFromResolvedFile
  fi
  # Archive ad-hoc signed; the Developer ID signature is applied below, inside-out,
  # by hand. That keeps team/profile settings out of the project and makes this
  # script the single place that decides how every nested binary is signed.
  xcodebuild -project FSearch.xcodeproj -scheme FSearch -configuration Release \
    -archivePath "$OUT/FSearch.xcarchive" -derivedDataPath "$DERIVED" -onlyUsePackageVersionsFromResolvedFile \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO archive
  [ -d "$APP" ] || fail "the archive has no app at $APP"
  echo "$STAMP" > "$OUT/prepared"
  if [ "$PHASE" = prepare ]; then
    echo "Prepared $APP. Run scripts/release.sh --sign $VERSION to sign, notarize and package it."
    exit 0
  fi
else
  [ -d "$APP" ] || fail "no archive at $APP: run scripts/release.sh --prepare $VERSION first"
  [ "$(cat "$OUT/prepared" 2>/dev/null)" = "$STAMP" ] \
    || fail "$APP was not prepared for $STAMP (run scripts/release.sh --prepare $VERSION again)"
fi
# Staging folder for the DMG contents; removed however the script ends.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

# Hardened runtime + secure timestamp are required for notarization.
sign() { codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$@"; }

# Inside-out, as Sparkle's docs prescribe: Autoupdate and Updater.app, then the
# framework, then our helper, then the app.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
SV="$SPARKLE/Versions/B"
[ -d "$SV" ] || fail "Sparkle.framework/Versions/B not found in $APP"
for c in "$SV/Autoupdate" "$SV/Updater.app"; do
  [ -e "$c" ] || fail "expected Sparkle component missing: $c"
done
# The app isn't sandboxed, so Sparkle's XPC services are unused and must not
# ship. Strip them here, not in a build phase: Xcode embeds the framework after
# post-build scripts, so an incremental build would put them back. Debug builds
# keep them, which is harmless. Removing them breaks the framework's seal; the
# signing below re-seals it.
rm -rf "$SV/XPCServices" "$SPARKLE/XPCServices"
if [ -e "$SV/XPCServices" ] || [ -e "$SPARKLE/XPCServices" ]; then fail "could not strip Sparkle's XPCServices from $APP"; fi
BUILT_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")
[ "$BUILT_VERSION" = "$BUILD" ] || fail "built CFBundleVersion is '$BUILT_VERSION', expected '$BUILD'"
sign "$SV/Autoupdate"
sign "$SV/Updater.app"
sign "$SPARKLE"
sign --identifier com.domfahey.fsearch.daemon "$APP/Contents/Helpers/fsearch"
sign --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# No nested binary may carry an entitlement that weakens the hardened runtime.
BAD_ENT='com.apple.security.get-task-allow|com.apple.security.cs.allow-jit|com.apple.security.cs.disable-library-validation|com.apple.security.cs.allow-dyld-environment-variables'
while IFS= read -r -d '' f; do
  file -b "$f" | grep -q 'Mach-O' || continue
  ENTS=$(codesign -d --entitlements - --xml "$f" 2>/dev/null || true)
  if grep -Eq "$BAD_ENT" <<<"$ENTS"; then fail "forbidden entitlement in $f"; fi
done < <(find "$APP" -type f -print0)   # includes the app's own executable

# DMG with the app and an /Applications symlink for drag-install.
DMG="$OUT/FSearch-$VERSION.dmg"
ditto "$APP" "$STAGE/FSearch.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname FSearch -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" ${NOTARY_KC[@]+"${NOTARY_KC[@]}"} --wait
xcrun stapler staple "$DMG"
# Notarization covered the app inside the DMG; staple the archive's identical app
# too so `stapler validate` can check it below.
xcrun stapler staple "$APP" || fail "stapling $APP failed"

# Verify the finished artifacts; any failure stops the release.
xcrun stapler validate "$APP" || fail "stapler validate failed for $APP"
xcrun stapler validate "$DMG" || fail "stapler validate failed for $DMG"
codesign --verify --deep --strict --verbose=2 "$APP" || fail "codesign verification failed for $APP"
spctl -a -t open --context context:primary-signature -v "$DMG" || fail "Gatekeeper rejected $DMG"
spctl -a -t exec -vv "$APP" || fail "Gatekeeper rejected $APP"

# Checksums to publish next to the DMG (verify with: shasum -a 256 -c FILE.dmg.sha256).
(cd "$OUT" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256") \
  || fail "could not write checksum for $DMG"
mkdir -p "$(dirname "$LAST_BUILD_FILE")"; echo "$BUILD" > "$LAST_BUILD_FILE"
echo "SHA-256:"; cat "$DMG.sha256"
echo "Now publish $DMG and $DMG.sha256 with appcast.xml (run Sparkle's generate_appcast on $OUT)."
