# Koe - macOS Dictation App

## Quick Reference
- macOS-only menu bar app (NOT iOS)
- Apple Silicon, macOS 14+
- Offline transcription via WhisperKit

## Commands (ALWAYS USE MAKE)

IMPORTANT: Always use `make` commands instead of raw `swift` commands. The Makefile handles paths, flags, and tooling correctly.

```
make build          # Debug build
make build-release  # Release build
make format         # SwiftFormat
make lint           # SwiftLint
make check          # All checks (run before commits)
make bundle         # Create signed .app
make test           # Run tests
make clean          # Clean build artifacts
make setup          # Install dev tools
```

Installer (Deno):
```
make installer-build
make installer-fmt
make installer-lint
```

If you notice a missing or improvable make target, suggest adding it to the Makefile.

## Architecture
Main app: KoeApp/Koe/
Packages: Packages/Koe*/

Key files for state changes:
- AppState.swift - Central observable state
- BackgroundModelService.swift - Model lifecycle
- RecordingCoordinator.swift - Recording orchestration

## Critical Patterns

### Model Switching (IMPORTANT)
When changing models, you MUST do BOTH:
1. `AppState.shared.selectedModel = model.rawValue`
2. `await RecordingCoordinator.shared.loadModel(name: model.rawValue)`

Only updating AppState makes UI show selected but model isn't loaded.

### MainActor Updates
Background services updating state need explicit dispatch:
```swift
Task { @MainActor in
    AppState.shared.someProperty = value
}
```
Even if the class is @MainActor, async operations may not be.

### Pipeline Blocking
Check `RecordingCoordinator.shared.isPipelineProcessing` before starting new recordings.

### Installer Progress
Use `fflush(stdout)` after print statements in installer code for progress visibility.

## Code Style
- @Observable + @MainActor (not ObservableObject)
- Actors for thread safety, NEVER @unchecked Sendable
- SwiftFormat enforced (make format)

## Commit Messages
- Never add AI attribution
- Never add "Co-Authored-By" lines
- Use conventional commits: feat:, fix:, refactor:
