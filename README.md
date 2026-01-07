# Koe 声

**Local voice-to-text dictation for macOS**

Koe is a lightweight, privacy-focused dictation app that converts speech to text using on-device AI. Your voice never leaves your Mac.

---

## Features

- **100% Local Processing** - All transcription happens on-device using [WhisperKit](https://github.com/argmaxinc/WhisperKit). No cloud, no subscriptions, no data collection.
- **Global Hotkey** - Trigger dictation from anywhere with `Cmd+Shift+Space` (customizable).
- **System-Wide** - Transcribed text auto-inserts at your cursor in any application.
- **Multiple Models** - Choose from tiny, base, small, medium, or large-v3 for your speed/accuracy preference.
- **Multi-Language** - Auto-detect or specify your language (100+ supported).
- **Transcription History** - Access recent transcriptions from the menu bar.

## Requirements

- macOS 14.0+ (Sonoma or later)
- Apple Silicon Mac (M1/M2/M3/M4)

## Installation

### Homebrew (coming soon)

```bash
brew install --cask koe
```

### Manual

1. Download the latest release from [Releases](https://github.com/whatiskadudoing/koe/releases)
2. Move `Koe.app` to `/Applications`
3. Launch and grant Microphone & Accessibility permissions

## Usage

1. Press `Cmd+Shift+Space` (or your configured hotkey)
2. Speak
3. Release - text appears at your cursor

### Recording Modes

| Mode | Behavior |
|------|----------|
| **Hold** | Record while holding the hotkey |
| **Toggle** | Press to start, press again to stop |

## Building from Source

```bash
git clone https://github.com/whatiskadudoing/koe.git
cd koe
open Koe.xcodeproj
```

Build with Xcode 15.0+ and run.

## Privacy

Koe processes everything locally:

- No internet connection required after model download
- No telemetry or analytics
- No account required
- Audio is never stored or transmitted

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) by Argmax for on-device Whisper inference
- [OpenAI Whisper](https://github.com/openai/whisper) for the speech recognition model

---

<p align="center">
  <sub>声 (koe) - voice</sub>
</p>
