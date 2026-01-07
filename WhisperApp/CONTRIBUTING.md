# Contributing to Koe

Thanks for your interest in contributing to Koe! This document outlines the process for contributing to this project.

## Getting Started

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/koe.git
   cd koe
   ```
3. Open `WhisperApp/WhisperApp.xcodeproj` in Xcode

## Development Setup

### Requirements

- macOS 14.0+ (Sonoma)
- Xcode 15.0+
- Apple Silicon Mac (M1/M2/M3/M4)

### Building

```bash
cd WhisperApp
open WhisperApp.xcodeproj
```

Build and run with `Cmd+R`.

## Making Changes

### Branch Naming

- `feature/` - New features
- `fix/` - Bug fixes
- `docs/` - Documentation updates

Example: `feature/add-custom-hotkey`

### Commit Messages

Write clear, concise commit messages:

```
Add custom hotkey configuration

- Add preferences UI for hotkey selection
- Store hotkey in UserDefaults
- Update global hotkey listener
```

### Code Style

- Follow Swift conventions and SwiftUI best practices
- Use meaningful variable and function names
- Keep functions focused and small
- Add comments for complex logic

## Pull Requests

1. Create a feature branch from `main`
2. Make your changes
3. Test thoroughly on your machine
4. Push to your fork
5. Open a Pull Request

### PR Checklist

- [ ] Code builds without warnings
- [ ] Tested on Apple Silicon Mac
- [ ] Updated README if needed
- [ ] Added comments for complex code

## Reporting Issues

When reporting bugs, please include:

- macOS version
- Mac model (M1/M2/M3/M4)
- Steps to reproduce
- Expected vs actual behavior
- Console logs if relevant

## Feature Requests

Open an issue with:

- Clear description of the feature
- Use case / why it's needed
- Any implementation ideas

## Questions?

Open an issue with the `question` label.

---

Thank you for contributing to Koe!
