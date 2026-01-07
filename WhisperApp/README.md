# Whisper

<p align="center">
  <img src="docs/images/icon.png" alt="Whisper Icon" width="128" height="128">
</p>

<p align="center">
  <strong>Voice-to-text transcription for macOS using OpenAI Whisper</strong>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#usage">Usage</a> •
  <a href="#building">Building</a> •
  <a href="#contributing">Contributing</a>
</p>

---

Whisper is a native macOS app that transcribes your voice and types it wherever your cursor is. It runs entirely on-device using [WhisperKit](https://github.com/argmaxinc/WhisperKit) - no internet required, no data sent anywhere.

## Features

- **Hold-to-record**: Hold `Option+Space` to record, release to transcribe
- **Auto-type**: Transcribed text is automatically typed at your cursor position
- **100% Private**: All processing happens on-device using Apple's Neural Engine
- **Multiple Models**: Choose from tiny (fastest) to large-v3 (most accurate)
- **Multi-language**: Supports 99+ languages with auto-detection
- **Menu Bar App**: Lives in your menu bar with animated waveform indicator
- **Offline Ready**: Bundle models for complete offline use

## Demo

<p align="center">
  <img src="docs/images/demo.gif" alt="Whisper Demo" width="600">
</p>

## Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon (M1/M2/M3) or Intel Mac
- Microphone access
- Accessibility access (for auto-typing)

## Installation

### Quick Install (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/whatiskadudoing/koe/main/install.sh | bash
```

### Install with Specific Model

```bash
# Tiny model (~75MB) - Fastest
curl -fsSL https://raw.githubusercontent.com/whatiskadudoing/koe/main/install.sh | bash -s -- tiny

# Large model (~3GB) - Best accuracy
curl -fsSL https://raw.githubusercontent.com/whatiskadudoing/koe/main/install.sh | bash -s -- large-v3

# All models (~5GB) - Full offline capability
curl -fsSL https://raw.githubusercontent.com/whatiskadudoing/koe/main/install.sh | bash -s -- all
```

### Homebrew

```bash
# Default (tiny model)
brew install --cask whisper

# Other variants
brew install --cask whisper-large    # Large V3 model
brew install --cask whisper-full     # All models
```

### Manual Download

Download the DMG from [Releases](https://github.com/whatiskadudoing/koe/releases):

| Variant | Size | Description |
|---------|------|-------------|
| `Whisper-x.x.x.dmg` | ~15MB | No bundled model (downloads on first use) |
| `Whisper-x.x.x-tiny.dmg` | ~75MB | Tiny model - Fastest |
| `Whisper-x.x.x-base.dmg` | ~150MB | Base model - Fast |
| `Whisper-x.x.x-small.dmg` | ~500MB | Small model - Balanced |
| `Whisper-x.x.x-medium.dmg` | ~1.5GB | Medium model - Accurate |
| `Whisper-x.x.x-large-v3.dmg` | ~3GB | Large V3 - Best accuracy |
| `Whisper-x.x.x-all.dmg` | ~5GB | All models - Full offline |

## Usage

### Basic Usage

1. **Launch Whisper** - The app appears in your menu bar as an animated waveform
2. **Hold Option+Space** - Start recording (waveform turns red)
3. **Speak** - Say what you want to transcribe
4. **Release** - Text is automatically typed at your cursor

### Menu Bar States

| Color | State |
|-------|-------|
| 🔵 Blue | Loading model |
| ⚪ White | Ready/Idle |
| 🔴 Red | Recording |
| 🟠 Orange | Processing |

### Settings

Click the menu bar icon to access:
- **Model Selection**: Switch between different Whisper models
- **Language**: Auto-detect or select specific language
- **Settings**: Configure transcription mode and preferences

### Keyboard Shortcut

The default shortcut is `Option+Space` (hold to record). This works globally across all applications.

## Models

| Model | Size | Speed | Accuracy | Best For |
|-------|------|-------|----------|----------|
| tiny | 75MB | ⚡⚡⚡⚡⚡ | ⭐⭐ | Quick notes, commands |
| base | 150MB | ⚡⚡⚡⚡ | ⭐⭐⭐ | General use |
| small | 500MB | ⚡⚡⚡ | ⭐⭐⭐⭐ | Balanced |
| medium | 1.5GB | ⚡⚡ | ⭐⭐⭐⭐⭐ | High accuracy |
| large-v3 | 3GB | ⚡ | ⭐⭐⭐⭐⭐ | Best accuracy |

## Building from Source

### Prerequisites

- Xcode 15.0+
- Swift 5.9+
- macOS 13.0+

### Build

```bash
# Clone the repository
git clone https://github.com/whatiskadudoing/koe.git
cd WhisperApp

# Build (no bundled model)
./build-app.sh

# Build with bundled model
./build-app.sh tiny      # or base, small, medium, large-v3, all

# Create DMG for distribution
./create-dmg.sh tiny
```

### Development

```bash
# Build for development
swift build

# Run
.build/debug/WhisperApp
```

## Privacy

Whisper is designed with privacy as a core principle:

- **100% On-Device**: All speech recognition happens locally using Apple's Neural Engine
- **No Network Requests**: The app never sends audio or transcriptions anywhere
- **No Analytics**: No tracking, no telemetry, no data collection
- **No Account Required**: Just install and use
- **Open Source**: Audit the code yourself

## Troubleshooting

### "Whisper can't type" / Text not appearing

1. Open **System Settings** → **Privacy & Security** → **Accessibility**
2. Find **Whisper** and enable it
3. Restart Whisper if needed

### "Microphone access denied"

1. Open **System Settings** → **Privacy & Security** → **Microphone**
2. Find **Whisper** and enable it

### Model download stuck

- Check your internet connection
- Try a smaller model first (tiny)
- Check `~/Library/Application Support/WhisperApp/Models` for partial downloads

### App not responding

- Check Activity Monitor for WhisperApp
- Try quitting and restarting
- Check `/tmp/whisper_debug.log` for error messages

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Development Setup

1. Fork the repository
2. Clone your fork
3. Create a feature branch
4. Make your changes
5. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) - On-device Whisper implementation
- [OpenAI Whisper](https://github.com/openai/whisper) - Original Whisper model
- [Hugging Face](https://huggingface.co/argmaxinc/whisperkit-coreml) - Model hosting

## Support

- 🐛 [Report a bug](https://github.com/whatiskadudoing/koe/issues/new?template=bug_report.md)
- 💡 [Request a feature](https://github.com/whatiskadudoing/koe/issues/new?template=feature_request.md)
- 💬 [Discussions](https://github.com/whatiskadudoing/koe/discussions)

---

<p align="center">
  Made with ❤️ for the open source community
</p>
