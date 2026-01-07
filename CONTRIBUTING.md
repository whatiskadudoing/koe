# Contributing to Koe

Thanks for your interest in contributing to Koe! This document outlines the process for contributing to this project.

## Getting Started

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/koe.git
   cd koe
   ```
3. Install development tools:
   ```bash
   make setup
   ```

## Development Setup

### Requirements

- macOS 14.0+ (Sonoma)
- Xcode 16.0+ (for SwiftLint)
- Apple Silicon Mac (M1/M2/M3/M4)
- Deno v2.x (for installer)

### Project Structure

```
koe/
├── KoeApp/              # Main application (Swift Package)
│   ├── Koe/             # App source files
│   └── Package.swift    # SPM manifest
├── Packages/            # Modular packages
│   ├── KoeDomain/       # Core models & protocols
│   ├── KoeCore/         # Utilities & logging
│   ├── KoeAudio/        # Audio recording
│   ├── KoeTranscription/# WhisperKit integration
│   ├── KoeHotkey/       # Global hotkey
│   ├── KoeTextInsertion/# Text insertion
│   ├── KoeStorage/      # Persistence
│   └── KoeUI/           # SwiftUI components
├── installer/           # Deno-based installer
├── Makefile             # Development commands
└── .github/             # CI/CD workflows
```

### Building

```bash
# Debug build
make build

# Release build
make build-release

# Create signed .app bundle
make bundle

# Clean build artifacts
make clean
```

### Code Quality

```bash
# Format code (auto-fix)
make format

# Check formatting (CI mode)
make format-check

# Run SwiftLint
make lint

# Auto-fix lint issues
make lint-fix

# Run all checks
make check
```

### Installer

```bash
# Lint installer code
make installer-lint

# Format installer code
make installer-fmt

# Build installer binary
make installer-build
```

### All Commands

Run `make help` to see all available commands.

## Making Changes

### Branch Naming

- `feat/` - New features
- `fix/` - Bug fixes
- `docs/` - Documentation updates
- `refactor/` - Code refactoring

Example: `feat/add-custom-hotkey`

### Commit Messages

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add custom hotkey configuration
fix: resolve audio buffer overflow
docs: update installation instructions
refactor: simplify transcription pipeline
```

### Code Style

- Run `make format` before committing
- Run `make lint` to check for issues
- Follow Swift conventions and SwiftUI best practices
- Use meaningful variable and function names
- Keep functions focused and small

## Pull Requests

1. Create a feature branch from `main`
2. Make your changes
3. Run `make check` to verify all checks pass
4. Push to your fork
5. Open a Pull Request

### PR Checklist

- [ ] `make check` passes (format + lint)
- [ ] `make build` succeeds without warnings
- [ ] Tested on Apple Silicon Mac
- [ ] Updated docs if needed

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
