#!/bin/bash
#
# Koe Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/whatiskadudoing/koe/main/install.sh | bash
#

set -e

REPO="whatiskadudoing/koe"
APP_NAME="Koe.app"
INSTALL_DIR="/Applications"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo -e "${BLUE}声 Koe Installer${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo -e "${RED}Error: Koe only runs on macOS${NC}"
    exit 1
fi

# Check Apple Silicon
ARCH=$(uname -m)
if [[ "$ARCH" != "arm64" ]]; then
    echo -e "${RED}Error: Koe requires Apple Silicon (M1/M2/M3/M4)${NC}"
    exit 1
fi

echo "→ Fetching latest release..."

# Get latest release download URL
DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest" | grep "browser_download_url.*zip" | cut -d '"' -f 4)

if [[ -z "$DOWNLOAD_URL" ]]; then
    echo -e "${RED}Error: Could not find latest release${NC}"
    echo "Visit https://github.com/${REPO}/releases to download manually"
    exit 1
fi

# Create temp directory
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

echo "→ Downloading Koe..."
curl -sL "$DOWNLOAD_URL" -o "$TMP_DIR/Koe.zip"

echo "→ Installing to /Applications..."
unzip -q "$TMP_DIR/Koe.zip" -d "$TMP_DIR"

# Remove existing installation
if [[ -d "$INSTALL_DIR/$APP_NAME" ]]; then
    rm -rf "$INSTALL_DIR/$APP_NAME"
fi

# Move to Applications
mv "$TMP_DIR/$APP_NAME" "$INSTALL_DIR/"

# Remove quarantine attribute (bypass Gatekeeper for unsigned app)
xattr -cr "$INSTALL_DIR/$APP_NAME" 2>/dev/null || true

echo ""
echo -e "${GREEN}✓ Koe installed successfully!${NC}"
echo ""
echo "To get started:"
echo "  1. Open Koe from /Applications"
echo "  2. Grant Microphone & Accessibility permissions"
echo "  3. Press Cmd+Shift+Space to dictate"
echo ""
echo -e "${BLUE}声${NC} Enjoy!"
echo ""
