# Whisper Voice-to-Text

Two implementations available:
1. **WhisperApp/** - Native SwiftUI macOS app (recommended)
2. **Python version** - Original Python prototype

## Native SwiftUI App (Recommended)

### Quick Start

```bash
# Install XcodeGen
brew install xcodegen

# Generate and open project
cd WhisperApp
xcodegen generate
open WhisperApp.xcodeproj
```

Build and run with `Cmd+R` in Xcode.

### Features

- **Menu Bar Icon** - Changes based on state:
  - 🎤 Idle (mic icon)
  - 🔴 Recording (red dot)
  - ⚙️ Processing (spinner)

- **Main Window** - Click menu bar icon to open:
  - Large mic button to start/stop recording
  - Visual waveform feedback
  - Transcription display
  - History chips

- **WhisperKit** - Uses large-v3 model for best accuracy
  - Local processing (no cloud)
  - Optimized for Apple Silicon

### UI Design

Japanese-inspired minimalist aesthetic:
- Off-white background (washi paper)
- Deep indigo accent color
- Asymmetric layout
- Generous negative space
- Subtle waveform animation

### Project Structure

```
WhisperApp/
├── Package.swift
├── project.yml              # XcodeGen config
├── WhisperApp.entitlements
└── WhisperApp/
    ├── WhisperApp.swift     # Entry + menu bar
    ├── AppState.swift       # State management
    ├── ContentView.swift    # Main UI
    ├── AudioRecorder.swift  # Recording
    ├── TranscriberService.swift
    ├── SettingsView.swift
    └── Info.plist
```

---

## Python Version (Prototype)

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python main.py
```

Uses faster-whisper with hotkey activation.

---

## Model Options

| Model | Size | Speed | Accuracy |
|-------|------|-------|----------|
| tiny | 39 MB | Fastest | Good |
| base | 74 MB | Fast | Better |
| small | 244 MB | Medium | Good |
| large-v3 | 1.5 GB | Slower | Best |

Default: `large-v3` for best quality.
