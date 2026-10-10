#!/usr/bin/env bash
# Build, sign, notarize and package a release DMG. Run from anywhere.
# Usage: scripts/release.sh [VERSION]   (VERSION defaults to the exact tag at HEAD, minus a leading "v")
# CFBundleShortVersionString = VERSION; CFBundleVersion = `git rev-list --count HEAD`
# (needs full history), which must exceed the last released build recorded in
# $LAST_BUILD_FILE (default release/last-build; written after a successful run).
# Prerequisites (checked up front): DEVELOPER_ID, a notarytool profile, a real Sparkle key.
# Also needs Xcode, xcodegen, Rust (for build-daemon.sh) and a full git clone.
#
# Writes only under build/release/ and release/last-build. It never touches the
# real index, ~/Library/Application Support/FSearch, LaunchAgents or ~/.local/bin.
# Exit codes: 0 released; 1 any failed check or step (the message says which).
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE=${NOTARY_PROFILE:-fsearch-notary}
ENTITLEMENTS=App/Resources/FSearch.entitlements
# CI stores the notary profile in a temporary keychain and exports KEYCHAIN.
NOTARY_KC=()
[ -n "${KEYCHAIN:-}" ] && NOTARY_KC=(--keychain "$KEYCHAIN")
fail() { echo "release.sh: $*" >&2; exit 1; }

[ -n "${DEVELOPER_ID:-}" ] || fail "DEVELOPER_ID is not set (e.g. 'Developer ID Application: Your Name (TEAMID)')"
# Capture first: `... | grep -q` can SIGPIPE the producer and fail under pipefail.
IDENTITIES=$(security find-identity -v -p codesigning)
grep -qF "$DEVELOPER_ID" <<<"$IDENTITIES" \
  || fail "no codesigning identity matching '$DEVELOPER_ID' in the keychain"
xcrun notarytool history --keychain-profile "$PROFILE" ${NOTARY_KC[@]+"${NOTARY_KC[@]}"} >/dev/null 2>&1 \
  || fail "notarytool profile '$PROFILE' not found (xcrun notarytool store-credentials $PROFILE)"
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
LAST_BUILD_FILE=${LAST_BUILD_FILE:-release/last-build}
if [ -f "$LAST_BUILD_FILE" ]; then
  LAST=$(tr -d '[:space:]' < "$LAST_BUILD_FILE")
  [[ "$LAST" =~ ^[0-9]+$ ]] || fail "$LAST_BUILD_FILE does not hold a build number"
  [ "$BUILD" -gt "$LAST" ] \
    || fail "CFBundleVersion $BUILD is not greater than the last release's $LAST ($LAST_BUILD_FILE); Sparkle would not offer it"
fi
echo "Releasing $VERSION (build $BUILD)"
OUT=build/release
rm -rf "$OUT"; mkdir -p "$OUT"
# Staging folder for the DMG contents; removed however the script ends.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

scripts/build-daemon.sh
xcodegen generate
# Archive ad-hoc signed; the Developer ID signature is applied below, inside-out,
# by hand. That keeps team/profile settings out of the project and makes this
# script the single place that decides how every nested binary is signed.
xcodebuild -project FSearch.xcodeproj -scheme FSearch -configuration Release \
  -archivePath "$OUT/FSearch.xcarchive" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO archive
APP="$OUT/FSearch.xcarchive/Products/Applications/FSearch.app"

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
sign "$APP/Contents/Helpers/fsearch"
sign --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

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
