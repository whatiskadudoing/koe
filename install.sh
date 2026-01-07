#!/bin/bash
#
# Koe Installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/whatiskadudoing/koe/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/whatiskadudoing/koe/main/install.sh | bash -s -- tiny
#   curl -fsSL https://raw.githubusercontent.com/whatiskadudoing/koe/main/install.sh | bash -s -- base
#   curl -fsSL https://raw.githubusercontent.com/whatiskadudoing/koe/main/install.sh | bash -s -- small
#   curl -fsSL https://raw.githubusercontent.com/whatiskadudoing/koe/main/install.sh | bash -s -- medium
#   curl -fsSL https://raw.githubusercontent.com/whatiskadudoing/koe/main/install.sh | bash -s -- large
#

set -e

REPO="whatiskadudoing/koe"
APP_NAME="Koe.app"
INSTALL_DIR="/Applications"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
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

# Model selection
MODEL="$1"

if [[ -z "$MODEL" ]]; then
    # Interactive mode - ask user to choose
    echo -e "${BOLD}Choose a model:${NC}"
    echo ""
    echo -e "  ${CYAN}1)${NC} tiny   - Fast & lightweight     ${YELLOW}(~67MB)${NC}"
    echo -e "  ${CYAN}2)${NC} base   - Balanced               ${YELLOW}(~150MB)${NC}"
    echo -e "  ${CYAN}3)${NC} small  - Better accuracy        ${YELLOW}(~500MB)${NC}"
    echo -e "  ${CYAN}4)${NC} medium - High accuracy          ${YELLOW}(~1.5GB)${NC}"
    echo -e "  ${CYAN}5)${NC} large  - Best accuracy          ${YELLOW}(~3GB)${NC}"
    echo ""
    echo -e "  ${BOLD}Tip:${NC} Start with 'tiny' - you can download more models in Settings later."
    echo ""
    read -p "Enter choice [1-5, default=1]: " choice

    case "$choice" in
        1|"") MODEL="tiny" ;;
        2) MODEL="base" ;;
        3) MODEL="small" ;;
        4) MODEL="medium" ;;
        5) MODEL="large" ;;
        tiny|base|small|medium|large) MODEL="$choice" ;;
        *)
            echo -e "${RED}Invalid choice. Using 'tiny'.${NC}"
            MODEL="tiny"
            ;;
    esac
    echo ""
fi

# Validate model
case "$MODEL" in
    tiny) SIZE="~67MB" ;;
    base) SIZE="~150MB" ;;
    small) SIZE="~500MB" ;;
    medium) SIZE="~1.5GB" ;;
    large) SIZE="~3GB" ;;
    *)
        echo -e "${RED}Error: Invalid model '$MODEL'${NC}"
        echo ""
        echo "Available models: tiny, base, small, medium, large"
        echo ""
        echo "Usage:"
        echo "  curl ... | bash -s -- tiny    # Fast & lightweight"
        echo "  curl ... | bash -s -- base    # Balanced"
        echo "  curl ... | bash -s -- small   # Better accuracy"
        echo "  curl ... | bash -s -- medium  # High accuracy"
        echo "  curl ... | bash -s -- large   # Best accuracy"
        exit 1
        ;;
esac

echo -e "Selected: ${YELLOW}${BOLD}${MODEL}${NC} (${SIZE})"
echo ""

echo "→ Fetching latest release..."

# Get latest release download URL for selected model
DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest" | grep "browser_download_url.*Koe-${MODEL}.zip" | cut -d '"' -f 4)

if [[ -z "$DOWNLOAD_URL" ]]; then
    echo -e "${RED}Error: Koe-${MODEL}.zip not found in latest release${NC}"
    echo ""
    echo "This model may not be available yet."
    echo "Try: tiny, base"
    echo ""
    echo "Or visit: https://github.com/${REPO}/releases"
    exit 1
fi

# Create temp directory
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

echo "→ Downloading Koe (${MODEL})..."
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
echo "│  4. Press Cmd+Shift+Space to dictate   │"
echo "└────────────────────────────────────────┘"
echo ""
echo -e "Model: ${YELLOW}${MODEL}${NC} (download more in Settings)"
echo ""
echo -e "${BLUE}声${NC} Enjoy!"
echo ""
