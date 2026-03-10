#!/usr/bin/env bash
# release.sh — local build and release script for cbNP
# Usage: ./release.sh <version>   e.g. ./release.sh 3.1.0

set -euo pipefail

# ── helpers ──────────────────────────────────────────────────────────────────
die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "  $*"; }

# ── args ─────────────────────────────────────────────────────────────────────
[[ $# -eq 1 ]] || die "Usage: $0 <version>  (e.g. $0 3.1.0)"
VERSION="$1"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Version must be in X.Y.Z format, got: $VERSION"

TAG="v${VERSION}"
DMG_NAME="cbNP-${VERSION}-arm64.dmg"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── pre-flight checks ─────────────────────────────────────────────────────────
command -v uv         >/dev/null 2>&1 || die "'uv' not found — install it first"
command -v gh         >/dev/null 2>&1 || die "'gh' not found — install GitHub CLI first"
command -v git        >/dev/null 2>&1 || die "'git' not found"
command -v create-dmg >/dev/null 2>&1 || die "'create-dmg' not found — run: brew install create-dmg"

cd "$SCRIPT_DIR"

# Make sure working tree is clean
if [[ -n "$(git status --porcelain)" ]]; then
    die "Working tree is not clean. Commit or stash changes before releasing."
fi

# Make sure the tag does not already exist
if git rev-parse "$TAG" >/dev/null 2>&1; then
    die "Tag $TAG already exists. Choose a different version."
fi

# ── confirmation prompt ───────────────────────────────────────────────────────
echo ""
echo "========================================"
echo "  cbNP release summary"
echo "========================================"
echo "  Version  : $VERSION"
echo "  Tag      : $TAG"
echo "  DMG      : $DMG_NAME"
echo "  Branch   : $(git rev-parse --abbrev-ref HEAD)"
echo "  Remote   : $(git remote get-url origin)"
echo ""
echo "  Steps that will run:"
echo "   1. Update version in pyproject.toml"
echo "   2. Commit version bump"
echo "   3. uv sync"
echo "   4. uv run pyinstaller -y cbNP.spec"
echo "   5. create-dmg → $DMG_NAME  (App + Applications alias)"
echo "   6. git tag $TAG"
echo "   7. git push + git push --tags"
echo "   8. gh release create $TAG (attach $DMG_NAME)"
echo "========================================"
echo ""
read -r -p "Proceed? [y/N] " CONFIRM
[[ "${CONFIRM,,}" == "y" ]] || { echo "Aborted."; exit 0; }

# ── step 1 & 2 — bump version ─────────────────────────────────────────────────
echo ""
echo "--- [1/8] Updating pyproject.toml to $VERSION ---"
# Use sed to replace the version line (works on macOS BSD sed)
sed -i '' "s/^version = \".*\"/version = \"${VERSION}\"/" pyproject.toml
info "pyproject.toml updated"

echo "--- [2/8] Committing version bump ---"
git add pyproject.toml
git commit -m "chore: bump version to $VERSION"
info "Committed"

# ── step 3 — sync deps ────────────────────────────────────────────────────────
echo "--- [3/8] uv sync ---"
uv sync
info "Done"

# ── step 4 — build app bundle ────────────────────────────────────────────────
echo "--- [4/8] Building app bundle ---"
uv run pyinstaller -y cbNP.spec
info "Build complete → dist/cbNP.app"

# ── step 5 — create DMG ──────────────────────────────────────────────────────
echo "--- [5/8] Creating DMG ---"
rm -f "$DMG_NAME"

# Convert logo.png → temporary .icns for the DMG volume icon
ICNS_TMP="$(mktemp -d)/cbNP.icns"
ICONSET_TMP="$(mktemp -d)/cbNP.iconset"
mkdir -p "$ICONSET_TMP"
for size in 16 32 64 128 256 512; do
    sips -z $size $size assets/logo.png --out "$ICONSET_TMP/icon_${size}x${size}.png"    >/dev/null 2>&1
    sips -z $((size*2)) $((size*2)) assets/logo.png --out "$ICONSET_TMP/icon_${size}x${size}@2x.png" >/dev/null 2>&1
done
iconutil -c icns "$ICONSET_TMP" -o "$ICNS_TMP"

create-dmg \
    --volname "cbNP $VERSION" \
    --volicon "$ICNS_TMP" \
    --window-pos 200 120 \
    --window-size 540 380 \
    --icon-size 128 \
    --icon "cbNP.app" 130 175 \
    --app-drop-link 410 175 \
    --hide-extension "cbNP.app" \
    "$DMG_NAME" \
    dist/cbNP.app

info "Created $DMG_NAME"

# ── step 6 — tag ─────────────────────────────────────────────────────────────
echo "--- [6/8] Tagging $TAG ---"
git tag "$TAG"
info "Tagged $TAG"

# ── step 7 — push ─────────────────────────────────────────────────────────────
echo "--- [7/8] Pushing commits and tag ---"
git push origin HEAD
git push origin "$TAG"
info "Pushed"

# ── step 8 — GitHub release ──────────────────────────────────────────────────
echo "--- [8/8] Creating GitHub release $TAG ---"
gh release create "$TAG" \
    "$DMG_NAME" \
    --title "cbNP $VERSION" \
    --notes "cbNP $VERSION — macOS arm64"
info "Release created"

echo ""
echo "Done. cbNP $VERSION is live."
