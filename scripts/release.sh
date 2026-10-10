#!/usr/bin/env bash
# Build, sign, notarize and package a release DMG. Run from anywhere.
# Prerequisites (checked up front): DEVELOPER_ID, a notarytool profile, a real Sparkle key.
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

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" App/Resources/Info.plist)
OUT=build/release
rm -rf "$OUT"; mkdir -p "$OUT"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

scripts/build-daemon.sh
xcodegen generate
# Archive ad-hoc signed; the Developer ID signature is applied below, inside-out,
# by hand. That keeps team/profile settings out of the project and makes this
# script the single place that decides how every nested binary is signed.
xcodebuild -project FSearch.xcodeproj -scheme FSearch -configuration Release \
  -archivePath "$OUT/FSearch.xcarchive" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO archive
APP="$OUT/FSearch.xcarchive/Products/Applications/FSearch.app"

sign() { codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$@"; }

# Inside-out, as Sparkle's docs prescribe: its XPC services, Autoupdate and
# Updater.app, then the framework, then our helper, then the app.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
SV="$SPARKLE/Versions/B"
[ -d "$SV" ] || fail "Sparkle.framework/Versions/B not found in $APP"
for c in "$SV/XPCServices/Installer.xpc" "$SV/XPCServices/Downloader.xpc" "$SV/Autoupdate" "$SV/Updater.app"; do
  [ -e "$c" ] || fail "expected Sparkle component missing: $c"
done
sign "$SV/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SV/XPCServices/Downloader.xpc"
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
spctl -a -t open --context context:primary-signature -v "$DMG"
spctl -a -t exec -vv "$APP"
echo "Now run Sparkle's generate_appcast on $OUT and publish appcast.xml + the DMG."
