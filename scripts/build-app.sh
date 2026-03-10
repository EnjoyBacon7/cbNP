#!/usr/bin/env bash
set -euo pipefail

BINARY="${1:?Usage: build-app.sh <binary> <app_name> <version>}"
APP_NAME="${2:?}"
VERSION="${3:?}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
APP_DIR="${PROJECT_ROOT}/${APP_NAME}.app"

echo "Building ${APP_NAME}.app v${VERSION}..."

# Clean previous build
rm -rf "${APP_DIR}"

# Create .app bundle structure
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# Copy binary
cp "${PROJECT_ROOT}/${BINARY}" "${APP_DIR}/Contents/MacOS/${BINARY}"

# Copy mediaremote_adapter into Resources
if [ -d "${PROJECT_ROOT}/mediaremote_adapter" ]; then
    cp -R "${PROJECT_ROOT}/mediaremote_adapter" "${APP_DIR}/Contents/Resources/"
    echo "  Bundled mediaremote_adapter"
fi

# Generate Info.plist from template
sed -e "s/__BINARY__/${BINARY}/g" \
    -e "s/__APP_NAME__/${APP_NAME}/g" \
    -e "s/__VERSION__/${VERSION}/g" \
    "${SCRIPT_DIR}/Info.plist.template" > "${APP_DIR}/Contents/Info.plist"

# Generate .icns from logo.png if sips/iconutil are available
LOGO="${PROJECT_ROOT}/assets/logo.png"
if [ -f "${LOGO}" ] && command -v sips &>/dev/null && command -v iconutil &>/dev/null; then
    ICONSET=$(mktemp -d)/icon.iconset
    mkdir -p "${ICONSET}"

    for SIZE in 16 32 64 128 256 512; do
        sips -z ${SIZE} ${SIZE} "${LOGO}" --out "${ICONSET}/icon_${SIZE}x${SIZE}.png" &>/dev/null
        DOUBLE=$((SIZE * 2))
        sips -z ${DOUBLE} ${DOUBLE} "${LOGO}" --out "${ICONSET}/icon_${SIZE}x${SIZE}@2x.png" &>/dev/null
    done

    iconutil -c icns "${ICONSET}" -o "${APP_DIR}/Contents/Resources/icon.icns"
    rm -rf "$(dirname "${ICONSET}")"
    echo "  Generated icon.icns"
else
    echo "  Warning: sips/iconutil not available, skipping .icns generation"
fi

echo "Built ${APP_DIR}"
