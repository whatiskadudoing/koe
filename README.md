# Koe 声

**Local voice-to-text dictation for macOS**

Koe is a lightweight, privacy-focused dictation app that converts speech to text using on-device AI. Your voice never leaves your Mac.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/whatiskadudoing/koe/main/install.sh | bash
```

That's it. Open Koe from `/Applications` and start dictating with `Option+Space`.

---

## Features

- **100% Local Processing** - All transcription happens on-device using [WhisperKit](https://github.com/argmaxinc/WhisperKit). No cloud, no subscriptions, no data collection.
- **Global Hotkey** - Trigger dictation from anywhere with `Option+Space`.
- **System-Wide** - Transcribed text auto-inserts at your cursor in any application.
- **Multi-Language** - Supports English, Spanish, Portuguese, and more.
- **Transcription History** - Access recent transcriptions from the menu bar.

## Requirements

- macOS 14.0+ (Sonoma or later)
- Apple Silicon Mac (M1/M2/M3/M4)

## Usage

1. Press `Option+Space`
2. Speak
3. Release - text appears at your cursor

### Recording Modes

| Mode | Behavior |
|------|----------|
| **Hold** | Record while holding the hotkey |
| **Toggle** | Press to start, press again to stop |

## Privacy

Koe processes everything locally:

- No internet connection required
- No telemetry or analytics
- No account required
- Audio is never stored or transmitted

## License

MIT License - see [LICENSE](LICENSE) for details.

---

<p align="center">
  <sub>声 (koe) - voice</sub>
</p>
