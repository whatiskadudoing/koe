#!/bin/bash

# WhisperApp Installer
# Install WhisperApp with your preferred model variant
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/whatiskadudoing/koe/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/whatiskadudoing/koe/main/install.sh | bash -s -- tiny
#   curl -fsSL https://raw.githubusercontent.com/whatiskadudoing/koe/main/install.sh | bash -s -- large-v3
#   curl -fsSL https://raw.githubusercontent.com/whatiskadudoing/koe/main/install.sh | bash -s -- all
#
# Model options:
#   none      - No bundled model, smallest download (~15MB), downloads model on first use
#   tiny      - Tiny model bundled (~75MB) - Fastest, good for quick notes
#   base      - Base model bundled (~150MB) - Fast, better accuracy
#   small     - Small model bundled (~500MB) - Balanced speed/accuracy
#   medium    - Medium model bundled (~1.5GB) - High accuracy
#   large-v3  - Large V3 model bundled (~3GB) - Best accuracy
#   all       - All models bundled (~5GB) - Full offline capability

set -e

MODEL_VARIANT="${1:-tiny}"  # Default to tiny for good balance
REPO_URL="https://github.com/whatiskadudoing/koe"
VERSION="1.0.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              WhisperApp Installer v${VERSION}                    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Validate model variant
VALID_MODELS=("none" "tiny" "base" "small" "medium" "large-v3" "all")
valid=false
for m in "${VALID_MODELS[@]}"; do
    if [[ "$m" == "$MODEL_VARIANT" ]]; then
        valid=true
        break
    fi
done

if [[ "$valid" == "false" ]]; then
    echo -e "${RED}❌ Invalid model variant: $MODEL_VARIANT${NC}"
    echo "   Valid options: none, tiny, base, small, medium, large-v3, all"
    exit 1
fi

# Model descriptions
declare -A MODEL_DESC
MODEL_DESC[none]="No bundled model (~15MB) - Downloads on first use"
MODEL_DESC[tiny]="Tiny model (~75MB) - Fastest, good for quick notes"
MODEL_DESC[base]="Base model (~150MB) - Fast with better accuracy"
MODEL_DESC[small]="Small model (~500MB) - Balanced speed/accuracy"
MODEL_DESC[medium]="Medium model (~1.5GB) - High accuracy"
MODEL_DESC[large-v3]="Large V3 model (~3GB) - Best accuracy"
MODEL_DESC[all]="All models (~5GB) - Full offline capability"

echo -e "📦 Installing with: ${GREEN}${MODEL_DESC[$MODEL_VARIANT]}${NC}"
echo ""

# Check for macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo -e "${RED}❌ WhisperApp only runs on macOS${NC}"
    exit 1
fi

# Check macOS version (requires 13.0+)
macos_version=$(sw_vers -productVersion | cut -d. -f1)
if [[ "$macos_version" -lt 13 ]]; then
    echo -e "${RED}❌ WhisperApp requires macOS 13.0 or later${NC}"
    echo "   Your version: $(sw_vers -productVersion)"
    exit 1
fi

# Check for existing installation
if [[ -d "/Applications/Whisper.app" ]]; then
    echo -e "${YELLOW}⚠ Whisper.app already exists in /Applications${NC}"
    read -p "   Replace existing installation? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
    echo "   Removing existing installation..."
    rm -rf "/Applications/Whisper.app"
fi

# Create temp directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "📥 Downloading WhisperApp..."

# Download the appropriate DMG
DMG_NAME="Whisper-${VERSION}-${MODEL_VARIANT}.dmg"
DMG_URL="${REPO_URL}/releases/download/v${VERSION}/${DMG_NAME}"

# Try to download with progress
if command -v curl &> /dev/null; then
    curl -L --progress-bar "$DMG_URL" -o "$TEMP_DIR/Whisper.dmg" || {
        echo -e "${RED}❌ Failed to download WhisperApp${NC}"
        echo "   URL: $DMG_URL"
        echo ""
        echo "   Make sure the release exists at:"
        echo "   ${REPO_URL}/releases/tag/v${VERSION}"
        exit 1
    }
elif command -v wget &> /dev/null; then
    wget -q --show-progress "$DMG_URL" -O "$TEMP_DIR/Whisper.dmg" || {
        echo -e "${RED}❌ Failed to download WhisperApp${NC}"
        exit 1
    }
else
    echo -e "${RED}❌ Neither curl nor wget found${NC}"
    exit 1
fi

echo ""
echo "📦 Installing..."

# Mount DMG
hdiutil attach "$TEMP_DIR/Whisper.dmg" -quiet -nobrowse -mountpoint "$TEMP_DIR/mount"

# Copy app to Applications
cp -R "$TEMP_DIR/mount/Whisper.app" /Applications/

# Unmount DMG
hdiutil detach "$TEMP_DIR/mount" -quiet

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Installation Complete!                          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "🎉 WhisperApp has been installed to /Applications/Whisper.app"
echo ""
echo "📋 Next steps:"
echo "   1. Open Whisper from your Applications folder"
echo "   2. Grant microphone access when prompted"
echo "   3. Grant accessibility access in System Settings"
echo "   4. Hold Option+Space to record and transcribe!"
echo ""
echo "💡 Tip: The app runs in the menu bar. Look for the waveform icon!"
echo ""

# Offer to open the app
read -p "Open WhisperApp now? [Y/n] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    open /Applications/Whisper.app
fi
