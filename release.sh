#!/usr/bin/env bash
# release.sh — local build and release script for cbNP
# Usage: ./release.sh <version> [--yes]   e.g. ./release.sh 3.1.0

set -euo pipefail

# ── helpers ──────────────────────────────────────────────────────────────────
die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "  $*"; }

# ── args ─────────────────────────────────────────────────────────────────────
AUTO_YES=false
POSITIONAL=()
for arg in "$@"; do
    case "$arg" in
        --yes|-y) AUTO_YES=true ;;
        *) POSITIONAL+=("$arg") ;;
    esac
done
[[ ${#POSITIONAL[@]} -eq 1 ]] || die "Usage: $0 <version> [--yes]  (e.g. $0 3.1.0)"
VERSION="${POSITIONAL[0]}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Version must be in X.Y.Z format, got: $VERSION"

TAG="v${VERSION}"
DMG_NAME="cbNP-${VERSION}-arm64.dmg"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── pre-flight checks ─────────────────────────────────────────────────────────
command -v uv         >/dev/null 2>&1 || die "'uv' not found — install it first"
command -v gh         >/dev/null 2>&1 || die "'gh' not found — install GitHub CLI first"
command -v git        >/dev/null 2>&1 || die "'git' not found"
command -v create-dmg >/dev/null 2>&1 || die "'create-dmg' not found — run: npm install --global create-dmg  (or brew install sindresorhus/create-dmg/create-dmg)"

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
  echo "   5. create-dmg → $DMG_NAME  (App + Applications alias, auto-layout)"
echo "   6. git tag $TAG"
echo "   7. git push + git push --tags"
echo "   8. gh release create $TAG (attach $DMG_NAME)"
echo "========================================"
echo ""
if [[ "$AUTO_YES" == true ]]; then
    echo "  (--yes flag set, skipping confirmation)"
else
    read -r -p "Proceed? [y/N] " CONFIRM
    [[ "${CONFIRM,,}" == "y" ]] || { echo "Aborted."; exit 0; }
fi

# ── step 1 & 2 — bump version ─────────────────────────────────────────────────
echo ""
echo "--- [1/8] Updating pyproject.toml to $VERSION ---"
# Use sed to replace the version line (works on macOS BSD sed)
sed -i '' "s/^version = \".*\"/version = \"${VERSION}\"/" pyproject.toml
info "pyproject.toml updated"

echo "--- [2/8] Committing version bump ---"
git add pyproject.toml
if git diff --cached --quiet; then
    info "pyproject.toml already at $VERSION, skipping commit"
else
    git commit -m "chore: bump version to $VERSION"
    info "Committed"
fi

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

# create-dmg (sindresorhus) auto-generates App + Applications alias layout.
# It names the output after the app version; rename to our convention afterwards.
create-dmg --overwrite --dmg-title="cbNP $VERSION" dist/cbNP.app .
# The tool outputs e.g. "cbNP 3.0.1.dmg" — rename to our convention
CREATED_DMG="$(ls -1 "cbNP "*.dmg 2>/dev/null | head -1)"
[[ -n "$CREATED_DMG" ]] || die "create-dmg did not produce a DMG file"
mv "$CREATED_DMG" "$DMG_NAME"

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
