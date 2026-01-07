#!/bin/bash
#
# Koe Installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/whatiskadudoing/koe/main/install.sh | bash
#

set -e

REPO="whatiskadudoing/koe"
APP_NAME="Koe.app"
INSTALL_DIR="/Applications"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${BLUE}${BOLD}声 Koe Installer${NC}"
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
DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest" | grep "browser_download_url.*Koe.zip" | head -1 | cut -d '"' -f 4)

if [[ -z "$DOWNLOAD_URL" ]]; then
    echo -e "${RED}Error: Could not find Koe.zip in latest release${NC}"
    echo "Visit https://github.com/${REPO}/releases"
    exit 1
fi

# Create temp directory
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

echo "→ Downloading Koe..."
curl -L --progress-bar "$DOWNLOAD_URL" -o "$TMP_DIR/Koe.zip"

echo "→ Installing to /Applications..."
unzip -q "$TMP_DIR/Koe.zip" -d "$TMP_DIR"

# Remove existing installation
if [[ -d "$INSTALL_DIR/$APP_NAME" ]]; then
    rm -rf "$INSTALL_DIR/$APP_NAME"
fi

# Move to Applications
mv "$TMP_DIR/$APP_NAME" "$INSTALL_DIR/"

# Remove quarantine attribute
xattr -cr "$INSTALL_DIR/$APP_NAME" 2>/dev/null || true

echo ""
echo -e "${GREEN}${BOLD}✓ Koe installed successfully!${NC}"
echo ""
echo "┌────────────────────────────────────────┐"
echo "│  Getting Started:                      │"
echo "│                                        │"
echo "│  1. Open Koe from /Applications        │"
echo "│  2. Grant Microphone permission        │"
echo "│  3. Grant Accessibility permission     │"
echo "│  4. Press Option+Space to dictate      │"
echo "└────────────────────────────────────────┘"
echo ""
echo -e "${BLUE}声${NC} Enjoy!"
echo ""
