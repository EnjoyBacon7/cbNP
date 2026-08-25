#!/bin/bash
# Build, Developer ID-sign, notarize, and staple a cbNP release.
#
# Takes no version argument: the version is whatever is committed in the Xcode
# project. Use scripts/bump-version.sh to change it, commit that, then run this.
# Local dev builds keep using the free personal team configured in the project;
# this script builds unsigned and re-signs, so the two never fight over
# CODE_SIGN_IDENTITY.
#
# Prerequisites (one-time, see README):
#   - a "Developer ID Application" identity in the login keychain
#   - a notarytool keychain profile named $NOTARY_PROFILE
set -euo pipefail

NOTARY_PROFILE="${NOTARY_PROFILE:-cbNP-notary}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

BUILD_DIR="$REPO_ROOT/build"
APP="$BUILD_DIR/Build/Products/Release/cbNP.app"
ENTITLEMENTS="$REPO_ROOT/cbNP.xcodeproj/App.entitlements"
# Stable name, no version: the download link on bizeul.cam resolves
# /releases/latest/download/cbNP.dmg, which only works if every release ships
# this exact filename. The version lives in the tag.
DMG="$REPO_ROOT/cbNP.dmg"

VERSION="$(grep -m1 -E 'MARKETING_VERSION = ' cbNP.xcodeproj/project.pbxproj \
  | sed -E 's/.*= ([^;]+);.*/\1/')"
echo "==> releasing version $VERSION"

# --- guards -------------------------------------------------------------
# A published binary should be traceable to a commit. Uncommitted edits mean
# the artifact users download matches nothing in the history.
if [ -n "$(git status --porcelain)" ] && [ "${ALLOW_DIRTY:-0}" != "1" ]; then
  echo "error: working tree is dirty; commit first (or ALLOW_DIRTY=1 to override)." >&2
  git --no-pager status --short >&2
  exit 1
fi

if git rev-parse "v$VERSION" >/dev/null 2>&1; then
  echo "error: tag v$VERSION already exists. Bump the version first." >&2
  exit 1
fi

IDENTITY="$(security find-identity -v -p codesigning \
  | grep "Developer ID Application" \
  | head -1 | sed -E 's/.*"(.*)"/\1/')"
if [ -z "$IDENTITY" ]; then
  echo "error: no 'Developer ID Application' identity in the keychain." >&2
  echo "       Xcode > Settings > Accounts > LOGAMES > Manage Certificates >" >&2
  echo "       + > Developer ID Application" >&2
  exit 1
fi
echo "==> signing identity: $IDENTITY"

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "error: notarytool profile '$NOTARY_PROFILE' not found. Create it with:" >&2
  echo "       xcrun notarytool store-credentials $NOTARY_PROFILE \\" >&2
  echo "         --apple-id <your-apple-id> --team-id D793768BHW --password <app-specific-password>" >&2
  exit 1
fi

# --- build --------------------------------------------------------------
echo "==> building Release (unsigned; re-signed below)"
rm -rf "$BUILD_DIR" "$DMG"
xcodebuild -scheme cbNP -configuration Release -derivedDataPath "$BUILD_DIR" \
  CODE_SIGNING_ALLOWED=NO build >/dev/null

BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$APP/Contents/Info.plist")"
if [ "$BUILT_VERSION" != "$VERSION" ]; then
  echo "error: built app reports $BUILT_VERSION, expected $VERSION." >&2
  exit 1
fi

# --- sign, inside out ---------------------------------------------------
# Nested code must be signed before the enclosing bundle, or the outer
# signature seals a hash that no longer matches.
sign() {
  codesign --force --sign "$IDENTITY" --options runtime --timestamp "$@"
}

echo "==> signing nested binaries"
ADAPTER="$APP/Contents/Resources/mediaremote_adapter"
sign "$ADAPTER/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter"
sign "$ADAPTER/MediaRemoteAdapter.framework"
sign "$ADAPTER/MediaRemoteAdapterTestClient"

echo "==> signing app bundle"
sign --entitlements "$ENTITLEMENTS" "$APP"

echo "==> verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"

# --- package ------------------------------------------------------------
echo "==> building $DMG"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "cbNP" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --force --sign "$IDENTITY" --timestamp "$DMG"

# --- notarize -----------------------------------------------------------
echo "==> submitting to Apple for notarization (this takes a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# The real test: what Gatekeeper says about the app a user just downloaded.
echo "==> Gatekeeper assessment"
spctl --assess --type execute --verbose=4 "$APP"

echo
echo "Done. $DMG is signed, notarized, and stapled."
echo "Publish it — the asset name must stay cbNP.dmg for the download link:"
echo "  git tag v$VERSION && git push origin v$VERSION"
echo "  gh release create v$VERSION \"$DMG\" --title \"cbNP $VERSION\" --notes '...'"
