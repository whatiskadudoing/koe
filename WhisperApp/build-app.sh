#!/bin/bash

# Build script for WhisperApp
# Creates a proper macOS .app bundle with optional bundled models
#
# Usage:
#   ./build-app.sh                  # Build without bundled models (smallest, ~15MB)
#   ./build-app.sh tiny             # Bundle tiny model (~75MB total)
#   ./build-app.sh base             # Bundle base model (~150MB total)
#   ./build-app.sh small            # Bundle small model (~500MB total)
#   ./build-app.sh medium           # Bundle medium model (~1.5GB total)
#   ./build-app.sh large-v3         # Bundle large-v3 model (~3GB total)
#   ./build-app.sh all              # Bundle ALL models (~5GB total)

set -e

APP_NAME="Whisper"
BUNDLE_ID="com.whisperapp.Whisper"
VERSION="1.0.0"
MODEL_VARIANT="${1:-none}"  # Default to no bundled model

# Function to get model size
get_model_size() {
    case "$1" in
        tiny) echo "75MB" ;;
        base) echo "150MB" ;;
        small) echo "500MB" ;;
        medium) echo "1.5GB" ;;
        large-v3) echo "3GB" ;;
        *) echo "unknown" ;;
    esac
}

# Available models
MODELS=("tiny" "base" "small" "medium" "large-v3")

# Hugging Face repo for models
HF_REPO="argmaxinc/whisperkit-coreml"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    WhisperApp Builder                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Validate model variant
if [[ "$MODEL_VARIANT" != "none" && "$MODEL_VARIANT" != "all" ]]; then
    valid=false
    for m in "${MODELS[@]}"; do
        if [[ "$m" == "$MODEL_VARIANT" ]]; then
            valid=true
            break
        fi
    done
    if [[ "$valid" == "false" ]]; then
        echo "❌ Invalid model variant: $MODEL_VARIANT"
        echo "   Valid options: none, tiny, base, small, medium, large-v3, all"
        exit 1
    fi
fi

echo "📦 Model variant: $MODEL_VARIANT"
if [[ "$MODEL_VARIANT" == "all" ]]; then
    echo "   Will bundle ALL models (~5GB total)"
elif [[ "$MODEL_VARIANT" != "none" ]]; then
    echo "   Will bundle $MODEL_VARIANT model (~$(get_model_size "$MODEL_VARIANT"))"
else
    echo "   No models bundled (smallest build, models downloaded on first use)"
fi
echo ""

# Download model function
download_model() {
    local model_name=$1
    local dest_dir=$2

    local model_folder="openai_whisper-${model_name}"
    local model_path="${dest_dir}/${model_folder}"

    if [[ -d "$model_path" ]]; then
        echo "   ✓ Model $model_name already downloaded"
        return 0
    fi

    echo "   ⬇ Downloading $model_name model..."

    # Create temp directory for download
    local temp_dir=$(mktemp -d)

    # Use huggingface-cli if available, otherwise use curl
    if command -v huggingface-cli &> /dev/null; then
        huggingface-cli download "$HF_REPO" "$model_folder/*" --local-dir "$temp_dir" --quiet
        mv "$temp_dir/$model_folder" "$model_path"
    else
        # Fallback: download using curl from HuggingFace
        mkdir -p "$model_path"

        # Get file list from HuggingFace API
        local api_url="https://huggingface.co/api/models/${HF_REPO}/tree/main/${model_folder}"
        local files=$(curl -s "$api_url" | grep -o '"path":"[^"]*"' | sed 's/"path":"//g' | sed 's/"//g')

        for file in $files; do
            local filename=$(basename "$file")
            local download_url="https://huggingface.co/${HF_REPO}/resolve/main/${file}"
            echo "      Downloading $filename..."
            curl -sL "$download_url" -o "$model_path/$filename"
        done
    fi

    rm -rf "$temp_dir"
    echo "   ✓ Model $model_name downloaded"
}

# Build the Swift package
echo "🔨 Building WhisperApp..."
swift build -c release
echo "   ✓ Build complete"
echo ""

# Create app bundle structure
APP_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
MODELS_DIR="${RESOURCES_DIR}/Models"

echo "📁 Creating app bundle..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"
mkdir -p "${MODELS_DIR}"

# Copy executable
cp .build/release/WhisperApp "${MACOS_DIR}/${APP_NAME}"
echo "   ✓ Executable copied"

# Download and bundle models
if [[ "$MODEL_VARIANT" != "none" ]]; then
    echo ""
    echo "📥 Preparing models..."

    # Create Resources/Models if it doesn't exist
    mkdir -p "Resources/Models"

    if [[ "$MODEL_VARIANT" == "all" ]]; then
        for model in "${MODELS[@]}"; do
            download_model "$model" "Resources/Models"
            cp -r "Resources/Models/openai_whisper-${model}" "${MODELS_DIR}/"
        done
    else
        download_model "$MODEL_VARIANT" "Resources/Models"
        cp -r "Resources/Models/openai_whisper-${MODEL_VARIANT}" "${MODELS_DIR}/"
    fi

    echo "   ✓ Models bundled"
fi

# Determine default model (first available bundled model, or tiny)
if [[ "$MODEL_VARIANT" == "all" ]]; then
    DEFAULT_MODEL="tiny"
elif [[ "$MODEL_VARIANT" != "none" ]]; then
    DEFAULT_MODEL="$MODEL_VARIANT"
else
    DEFAULT_MODEL="tiny"
fi

# Create Info.plist with default model
cat > "${CONTENTS_DIR}/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Whisper needs microphone access to transcribe your voice.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Whisper needs accessibility access to type transcribed text.</string>
    <key>WhisperDefaultModel</key>
    <string>${DEFAULT_MODEL}</string>
    <key>WhisperBundledModels</key>
    <string>${MODEL_VARIANT}</string>
</dict>
</plist>
EOF

# Create entitlements file
cat > "${CONTENTS_DIR}/entitlements.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
EOF

# Calculate bundle size
BUNDLE_SIZE=$(du -sh "${APP_DIR}" | cut -f1)
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    Build Complete!                           ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "📦 App bundle: ${APP_DIR}"
echo "📊 Size: ${BUNDLE_SIZE}"
echo "🎯 Default model: ${DEFAULT_MODEL}"
if [[ "$MODEL_VARIANT" == "all" ]]; then
    echo "📚 Bundled models: all (tiny, base, small, medium, large-v3)"
elif [[ "$MODEL_VARIANT" != "none" ]]; then
    echo "📚 Bundled models: ${MODEL_VARIANT}"
else
    echo "📚 Bundled models: none (will download on first use)"
fi
echo ""
echo "To install:"
echo "   cp -r ${APP_DIR} /Applications/"
echo ""
echo "To create DMG for distribution:"
echo "   ./create-dmg.sh ${MODEL_VARIANT}"
