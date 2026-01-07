#!/bin/bash

# Release script for WhisperApp
# Builds and creates DMGs for all model variants
#
# Usage:
#   ./release.sh              # Build all variants
#   ./release.sh tiny         # Build only tiny variant
#   ./release.sh upload       # Build all + upload to GitHub

set -e

VERSION="1.0.0"
VARIANTS=("none" "tiny" "base" "small" "medium" "large-v3" "all")

# Check for upload flag
UPLOAD=false
SINGLE_VARIANT=""

if [[ "$1" == "upload" ]]; then
    UPLOAD=true
elif [[ -n "$1" ]]; then
    SINGLE_VARIANT="$1"
fi

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              WhisperApp Release Builder v${VERSION}              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Create releases directory
mkdir -p releases

if [[ -n "$SINGLE_VARIANT" ]]; then
    # Build single variant
    echo "Building variant: $SINGLE_VARIANT"
    echo ""
    ./build-app.sh "$SINGLE_VARIANT"
    ./create-dmg.sh "$SINGLE_VARIANT"

    if [[ "$SINGLE_VARIANT" == "none" ]]; then
        cp "build/Whisper-${VERSION}.dmg" "releases/"
    else
        cp "build/Whisper-${VERSION}-${SINGLE_VARIANT}.dmg" "releases/"
    fi
else
    # Build all variants
    for variant in "${VARIANTS[@]}"; do
        echo ""
        echo "════════════════════════════════════════════════════════════════"
        echo "Building variant: $variant"
        echo "════════════════════════════════════════════════════════════════"
        echo ""

        ./build-app.sh "$variant"
        ./create-dmg.sh "$variant"

        # Copy DMG to releases folder
        if [[ "$variant" == "none" ]]; then
            cp "build/Whisper-${VERSION}.dmg" "releases/"
        else
            cp "build/Whisper-${VERSION}-${variant}.dmg" "releases/"
        fi
    done
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                  Release Files Ready!                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "📁 Release files in ./releases/:"
ls -lh releases/*.dmg 2>/dev/null || echo "   No DMG files found"
echo ""

# Generate checksums
echo "📋 SHA256 Checksums:"
echo ""
cd releases
shasum -a 256 *.dmg 2>/dev/null | tee checksums.txt
cd ..
echo ""

# Upload to GitHub if requested
if [[ "$UPLOAD" == "true" ]]; then
    echo "📤 Uploading to GitHub..."

    # Check if gh is installed
    if ! command -v gh &> /dev/null; then
        echo "❌ GitHub CLI (gh) not found. Install with: brew install gh"
        exit 1
    fi

    # Check if logged in
    if ! gh auth status &> /dev/null; then
        echo "❌ Not logged into GitHub. Run: gh auth login"
        exit 1
    fi

    # Create release if it doesn't exist
    if ! gh release view "v${VERSION}" &> /dev/null; then
        echo "Creating release v${VERSION}..."
        gh release create "v${VERSION}" \
            --title "WhisperApp v${VERSION}" \
            --notes "## WhisperApp v${VERSION}

### Download Options

| Variant | Size | Description |
|---------|------|-------------|
| [Whisper-${VERSION}.dmg](./Whisper-${VERSION}.dmg) | ~15MB | No bundled model (downloads on first use) |
| [Whisper-${VERSION}-tiny.dmg](./Whisper-${VERSION}-tiny.dmg) | ~75MB | Tiny model - Fastest |
| [Whisper-${VERSION}-base.dmg](./Whisper-${VERSION}-base.dmg) | ~150MB | Base model - Fast |
| [Whisper-${VERSION}-small.dmg](./Whisper-${VERSION}-small.dmg) | ~500MB | Small model - Balanced |
| [Whisper-${VERSION}-medium.dmg](./Whisper-${VERSION}-medium.dmg) | ~1.5GB | Medium model - Accurate |
| [Whisper-${VERSION}-large-v3.dmg](./Whisper-${VERSION}-large-v3.dmg) | ~3GB | Large V3 - Best accuracy |
| [Whisper-${VERSION}-all.dmg](./Whisper-${VERSION}-all.dmg) | ~5GB | All models - Full offline |

### Installation

\`\`\`bash
# Quick install (tiny model - recommended)
curl -fsSL https://raw.githubusercontent.com/whatiskadudoing/koe/main/install.sh | bash

# Install with specific model
curl -fsSL https://raw.githubusercontent.com/whatiskadudoing/koe/main/install.sh | bash -s -- large-v3
\`\`\`

### Requirements
- macOS 13.0 (Ventura) or later
- Apple Silicon or Intel Mac
"
    fi

    # Upload all DMGs
    for dmg in releases/*.dmg; do
        echo "Uploading $(basename "$dmg")..."
        gh release upload "v${VERSION}" "$dmg" --clobber
    done

    echo ""
    echo "✅ Release uploaded to GitHub!"
    echo "   https://github.com/whatiskadudoing/koe/releases/tag/v${VERSION}"
fi

echo ""
echo "Next steps:"
echo "   1. Review files in ./releases/"
echo "   2. Upload to GitHub: ./release.sh upload"
echo "   3. Update homebrew cask with SHA256 checksums"
