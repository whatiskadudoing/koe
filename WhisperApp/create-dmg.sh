#!/bin/bash

# Create DMG for WhisperApp distribution
# Requires: create-dmg (brew install create-dmg)
#
# Usage:
#   ./create-dmg.sh              # Creates DMG with whatever is in build/
#   ./create-dmg.sh tiny         # Creates DMG named Whisper-1.0.0-tiny.dmg
#   ./create-dmg.sh large-v3     # Creates DMG named Whisper-1.0.0-large-v3.dmg
#   ./create-dmg.sh all          # Creates DMG named Whisper-1.0.0-all.dmg

set -e

APP_NAME="Whisper"
VERSION="1.0.0"
MODEL_VARIANT="${1:-none}"
APP_PATH="build/${APP_NAME}.app"

# Create DMG name based on variant
if [[ "$MODEL_VARIANT" == "none" ]]; then
    DMG_NAME="${APP_NAME}-${VERSION}.dmg"
else
    DMG_NAME="${APP_NAME}-${VERSION}-${MODEL_VARIANT}.dmg"
fi

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    DMG Creator                               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check if app bundle exists
if [ ! -d "${APP_PATH}" ]; then
    echo "❌ Error: App bundle not found at ${APP_PATH}"
    echo ""
    echo "Run build-app.sh first:"
    echo "   ./build-app.sh ${MODEL_VARIANT}"
    exit 1
fi

# Check if create-dmg is installed
if ! command -v create-dmg &> /dev/null; then
    echo "📥 Installing create-dmg..."
    brew install create-dmg
fi

# Remove old DMG if exists
rm -f "build/${DMG_NAME}"

echo "📀 Creating DMG: ${DMG_NAME}"
echo ""

# Create DMG with create-dmg tool
create-dmg \
    --volname "${APP_NAME}" \
    --volicon "${APP_PATH}/Contents/Resources/AppIcon.icns" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "${APP_NAME}.app" 150 190 \
    --hide-extension "${APP_NAME}.app" \
    --app-drop-link 450 190 \
    --no-internet-enable \
    "build/${DMG_NAME}" \
    "${APP_PATH}" \
    2>/dev/null || {
        # Fallback to simple DMG creation if create-dmg fails
        echo "⚠ Falling back to simple DMG creation..."
        hdiutil create -volname "${APP_NAME}" -srcfolder "${APP_PATH}" -ov -format UDZO "build/${DMG_NAME}"
    }

# Calculate DMG size
DMG_SIZE=$(du -h "build/${DMG_NAME}" | cut -f1)

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    DMG Created!                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "📀 DMG file: build/${DMG_NAME}"
echo "📊 Size: ${DMG_SIZE}"
echo ""
echo "SHA256 checksum (for Homebrew/releases):"
shasum -a 256 "build/${DMG_NAME}"
echo ""
echo "To upload to GitHub releases:"
echo "   gh release upload v${VERSION} build/${DMG_NAME}"
