# Contributing to Whisper

First off, thank you for considering contributing to Whisper! It's people like you that make Whisper such a great tool.

## Code of Conduct

This project and everyone participating in it is governed by our [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check existing issues as you might find out that you don't need to create one. When you are creating a bug report, please include as many details as possible:

- **Use a clear and descriptive title**
- **Describe the exact steps to reproduce the problem**
- **Provide specific examples** (code snippets, screenshots, etc.)
- **Describe the behavior you observed and what you expected**
- **Include your macOS version and Mac model**
- **Include the Whisper model you were using**
- **Attach logs from `/tmp/whisper_debug.log` if relevant**

### Suggesting Features

Feature suggestions are tracked as GitHub issues. When creating a feature request:

- **Use a clear and descriptive title**
- **Provide a detailed description of the suggested feature**
- **Explain why this feature would be useful**
- **List any alternatives you've considered**

### Pull Requests

1. Fork the repo and create your branch from `main`
2. If you've added code that should be tested, add tests
3. Ensure your code follows the existing style
4. Make sure your code builds without warnings
5. Write a clear PR description

## Development Setup

### Prerequisites

- macOS 13.0 or later
- Xcode 15.0 or later
- Swift 5.9 or later

### Getting Started

```bash
# Fork and clone the repository
git clone https://github.com/whatiskadudoing/koe.git
cd WhisperApp

# Build the project
swift build

# Run in development mode
.build/debug/WhisperApp
```

### Project Structure

```
WhisperApp/
├── WhisperApp/           # Main source code
│   ├── WhisperApp.swift  # App entry point & menu bar
│   ├── AppState.swift    # Global app state
│   ├── TranscriberService.swift  # Whisper transcription
│   ├── RecordingService.swift    # Audio recording & VAD
│   ├── HotkeyManager.swift       # Global hotkey handling
│   ├── ContentView.swift         # Main UI
│   ├── SettingsView.swift        # Settings UI
│   └── RecordingOverlay.swift    # Recording overlay UI
├── Package.swift         # Swift package manifest
├── build-app.sh          # Build script
├── create-dmg.sh         # DMG creation script
├── install.sh            # User installation script
└── release.sh            # Release automation
```

### Building

```bash
# Debug build
swift build

# Release build
swift build -c release

# Build app bundle with model
./build-app.sh tiny

# Create DMG
./create-dmg.sh tiny
```

## Style Guidelines

### Swift Style

- Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- Use meaningful variable and function names
- Keep functions focused and small
- Add comments for complex logic
- Use `// MARK:` comments to organize code sections

### Commit Messages

- Use the present tense ("Add feature" not "Added feature")
- Use the imperative mood ("Move cursor to..." not "Moves cursor to...")
- Limit the first line to 72 characters or less
- Reference issues and pull requests when relevant

Example:
```
Add support for custom hotkey configuration

- Add HotkeySettings view for customization
- Store hotkey preferences in UserDefaults
- Update HotkeyManager to use custom keys

Fixes #123
```

### Code Organization

- Group related functionality together
- Use extensions to organize protocol conformances
- Keep files focused on a single responsibility
- Prefer composition over inheritance

## Testing

### Manual Testing Checklist

Before submitting a PR, please test:

- [ ] App launches without errors
- [ ] Menu bar icon appears and animates correctly
- [ ] Option+Space starts/stops recording
- [ ] Transcription works and text is typed
- [ ] Model switching works
- [ ] Settings are saved and restored
- [ ] App works after restart

### Debug Logging

Debug logs are written to `/tmp/whisper_debug.log`. Include relevant logs when reporting issues.

## Release Process

1. Update version in `build-app.sh`, `create-dmg.sh`, `install.sh`, `release.sh`
2. Update CHANGELOG.md
3. Create a PR with version bump
4. After merge, tag the release: `git tag v1.0.0`
5. Push tags: `git push --tags`
6. Run `./release.sh upload` to build and upload all variants

## Questions?

Feel free to open a [Discussion](https://github.com/whatiskadudoing/koe/discussions) if you have questions or want to discuss ideas before implementing them.

## Recognition

Contributors will be recognized in our README and release notes. Thank you for helping make Whisper better!
