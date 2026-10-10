#!/usr/bin/env bash
# Build, sign, notarize and package a release DMG. Run from anywhere.
# Prerequisites (checked up front): DEVELOPER_ID, a notarytool profile, a real Sparkle key.
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE=${NOTARY_PROFILE:-fsearch-notary}
fail() { echo "release.sh: $*" >&2; exit 1; }

[ -n "${DEVELOPER_ID:-}" ] || fail "DEVELOPER_ID is not set (e.g. 'Developer ID Application: Your Name (TEAMID)')"
security find-identity -v -p codesigning | grep -qF "$DEVELOPER_ID" \
  || fail "no codesigning identity matching '$DEVELOPER_ID' in the keychain"
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
  || fail "notarytool profile '$PROFILE' not found (xcrun notarytool store-credentials $PROFILE)"
KEY=$(/usr/libexec/PlistBuddy -c "Print SUPublicEDKey" App/Resources/Info.plist)
{ [ -n "$KEY" ] && [ "$KEY" != "REPLACE_WITH_SPARKLE_PUBLIC_KEY" ]; } \
  || fail "SUPublicEDKey in App/Resources/Info.plist is still the placeholder (see docs/release-checklist.md)"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" App/Resources/Info.plist)
OUT=build/release
rm -rf "$OUT"; mkdir -p "$OUT"

scripts/build-daemon.sh
xcodegen generate
xcodebuild -project FSearch.xcodeproj -scheme FSearch -configuration Release \
  -archivePath "$OUT/FSearch.xcarchive" \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID" OTHER_CODE_SIGN_FLAGS="--timestamp" archive
APP="$OUT/FSearch.xcarchive/Products/Applications/FSearch.app"

# Inside-out: nested code first, then the app.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE" ]; then
  find "$SPARKLE" \( -name '*.xpc' -o -name '*.app' \) -prune -print0 | while IFS= read -r -d '' c; do
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$c"
  done
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$SPARKLE"
fi
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP/Contents/Helpers/fsearch"
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
codesign --verify --deep --strict "$APP"

DMG="$OUT/FSearch-$VERSION.dmg"
hdiutil create -volname FSearch -srcfolder "$APP" -ov -format UDZO "$DMG"
codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG"
echo "Now run Sparkle's generate_appcast on $OUT and publish appcast.xml + the DMG."
