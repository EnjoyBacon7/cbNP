#!/bin/bash
# Set the marketing version and increment the build number.
#
# Deliberately separate from release.sh: bumping the version edits tracked
# source, and a build script that mutates the repo as a side effect leaves the
# tree dirty when a later step fails. Bump, review, commit, then release.
set -euo pipefail

VERSION="${1:-}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: scripts/bump-version.sh <major.minor.patch>   e.g. 4.1.0" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PBXPROJ="$REPO_ROOT/cbNP.xcodeproj/project.pbxproj"

CURRENT="$(grep -m1 -E 'MARKETING_VERSION = ' "$PBXPROJ" | sed -E 's/.*= ([^;]+);.*/\1/')"
BUILD="$(grep -m1 -E 'CURRENT_PROJECT_VERSION = ' "$PBXPROJ" | sed -E 's/.*= ([^;]+);.*/\1/')"
NEXT_BUILD=$(( BUILD + 1 ))

echo "marketing version: $CURRENT -> $VERSION"
echo "build number:      $BUILD -> $NEXT_BUILD"

# Applied to every build configuration: Debug and Release must not drift, or
# the version you test is not the version you ship.
/usr/bin/sed -i '' -E \
  -e "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $VERSION;/g" \
  -e "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $NEXT_BUILD;/g" \
  "$PBXPROJ"

echo
git -C "$REPO_ROOT" --no-pager diff --stat -- "$PBXPROJ"
echo
echo "Review, then commit before releasing:"
echo "  git commit -am 'chore: bump version to $VERSION'"
echo "  scripts/release.sh"
