#!/bin/bash
# Build, package, and verify a cbNP release DMG.
#
# Takes no version argument: the version is whatever is committed in the Xcode
# project. Use scripts/bump-version.sh to change it, commit that, then run this.
#
# cbNP ships development-signed and not notarized. There is no Developer ID
# Application certificate for this project, so Gatekeeper blocks the first
# launch and the README tells users how to allow it. Nothing here needs Apple
# credentials, an app-specific password, or network access.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

BUILD_DIR="$REPO_ROOT/build"
APP="$BUILD_DIR/Build/Products/Release/cbNP.app"

VERSION="$(grep -m1 -E 'MARKETING_VERSION = ' cbNP.xcodeproj/project.pbxproj \
  | sed -E 's/.*= ([^;]+);.*/\1/')"
# Versioned name: the README download link points at this exact filename, so it
# has to be bumped there on every release.
DMG="$REPO_ROOT/cbNP-$VERSION.dmg"
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

# --- build --------------------------------------------------------------
# Signed by the project's own automatic "Apple Development" identity, which
# also applies App.entitlements. No re-signing step, so local development and
# release builds cannot disagree about the identity.
echo "==> building Release"
rm -rf "$BUILD_DIR" "$DMG"
xcodebuild -scheme cbNP -configuration Release -derivedDataPath "$BUILD_DIR" \
  build >/dev/null

BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$APP/Contents/Info.plist")"
if [ "$BUILT_VERSION" != "$VERSION" ]; then
  echo "error: built app reports $BUILT_VERSION, expected $VERSION." >&2
  exit 1
fi

echo "==> verifying signature"
codesign --verify --strict --verbose=2 "$APP"

# --- package ------------------------------------------------------------
echo "==> building $DMG"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "cbNP" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

# --- verify what users actually download --------------------------------
# Check the copy inside the image, not the one that was staged: a bad copy or a
# broken signature should fail here, not on someone else's Mac.
echo "==> verifying packaged app"
MOUNT="$(hdiutil attach "$DMG" -nobrowse -readonly | grep -o '/Volumes/.*' | head -1)"
trap 'hdiutil detach "$MOUNT" >/dev/null 2>&1 || true; rm -rf "$STAGE"' EXIT

PACKAGED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$MOUNT/cbNP.app/Contents/Info.plist")"
if [ "$PACKAGED_VERSION" != "$VERSION" ]; then
  echo "error: packaged app reports $PACKAGED_VERSION, expected $VERSION." >&2
  exit 1
fi
codesign --verify --strict "$MOUNT/cbNP.app"

hdiutil detach "$MOUNT" >/dev/null
trap 'rm -rf "$STAGE"' EXIT

echo
echo "Done. $(basename "$DMG") is built and verified (development-signed, not notarized)."
echo "Publish it, then point the README download link at the new asset:"
echo "  git tag v$VERSION && git push origin v$VERSION"
echo "  gh release create v$VERSION \"$DMG\" --title \"cbNP $VERSION\" --notes '...'"
