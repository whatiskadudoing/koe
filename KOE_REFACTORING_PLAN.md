# Koe (声) - Complete Refactoring Plan

> **Koe** (声) means "voice" in Japanese.

---

## Progress Summary

| Phase | Status | Notes |
|-------|--------|-------|
| 1. Domain Layer (KoeDomain) | ✅ Complete | Protocols, models, errors |
| 2. @Observable Migration | ✅ Complete | AppState, views updated |
| 3. Service Extraction | ✅ Complete | All service packages created |
| 4. Storage Layer (KoeStorage) | ✅ Complete | UserDefaultsTranscriptionRepository |
| 5. UI Components (KoeUI) | ✅ Complete | Colors, WaveformView, KeyCap |
| 6. MenuBarExtra | ⏸️ Deferred | Complex rewrite needed |
| 7. Testing | ⏸️ Deferred | Requires Xcode |
| 8. Naming (Whisper → Koe) | ✅ Complete | Info.plist, paths, messages updated |

### Created Packages

```
Packages/
├── KoeDomain/          # Protocols, models, errors
├── KoeCore/            # Logger, extensions
├── KoeAudio/           # AVAudioEngineRecorder, VAD, AudioLevelMonitor
├── KoeTranscription/   # WhisperKitTranscriber
├── KoeHotkey/          # KoeHotkeyManager
├── KoeTextInsertion/   # Text insertion service
├── KoeStorage/         # Transcription storage
└── KoeUI/              # Design system, components
```

---

## Table of Contents

1. [Current State Analysis](#1-current-state-analysis)
2. [Architecture Vision](#2-architecture-vision)
3. [Target Structure](#3-target-structure)
4. [Phase 1: Domain Layer](#phase-1-domain-layer)
5. [Phase 2: @Observable Migration](#phase-2-observable-migration)
6. [Phase 3: Service Extraction](#phase-3-service-extraction)
7. [Phase 4: Storage Layer](#phase-4-storage-layer)
8. [Phase 5: UI Refactoring](#phase-5-ui-refactoring)
9. [Phase 6: Menu Bar Modernization](#phase-6-menu-bar-modernization)
10. [Phase 7: Testing](#phase-7-testing)
11. [Phase 8: Naming & Cleanup](#phase-8-naming--cleanup)
12. [File-by-File Migration Guide](#file-by-file-migration-guide)

---

## 1. Current State Analysis

### Current Files

| File | Lines | Responsibility | Issues |
|------|-------|----------------|--------|
| `RecordingService.swift` | 635 | Audio recording, VAD, transcription coordination, text insertion | **Monolithic** - does 5+ things |
| `WhisperApp.swift` | 522 | App entry, AppDelegate, menu bar icon, model loading | **Too large** - mixed concerns |
| `TranscriberService.swift` | 325 | WhisperKit loading, transcription | **Tightly coupled** to WhisperKit |
| `ContentView.swift` | 343 | Main UI, 8 sub-components inline | **Should extract** components |
| `RecordingOverlay.swift` | 276 | Overlay window, waveform views | OK but uses old patterns |
| `AppState.swift` | 80 | State management, history storage | **Uses ObservableObject**, storage inline |
| `HotkeyManager.swift` | 37 | Global hotkey | **Clean** - minimal changes needed |
| `SettingsView.swift` | 105 | Settings UI | Minor cleanup needed |

### Current Problems

```
┌─────────────────────────────────────────────────────────────────────┐
│                     CURRENT ARCHITECTURE                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ┌─────────────────────────────────────────────────────────┐       │
│   │              RecordingService (635 lines)                │       │
│   │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────────────┐│       │
│   │  │  Audio  │ │   VAD   │ │Transcr. │ │  Text Insertion ││       │
│   │  │Recording│ │Detection│ │  Coord  │ │  (CGEvents +    ││       │
│   │  │(Engine) │ │         │ │         │ │   Clipboard)    ││       │
│   │  └─────────┘ └─────────┘ └─────────┘ └─────────────────┘│       │
│   └─────────────────────────────────────────────────────────┘       │
│                          ↓                                           │
│   ┌─────────────────────────────────────────────────────────┐       │
│   │           TranscriberService (tightly coupled)           │       │
│   │                    WhisperKit                            │       │
│   └─────────────────────────────────────────────────────────┘       │
│                          ↓                                           │
│   ┌─────────────────────────────────────────────────────────┐       │
│   │                    AppState                              │       │
│   │  ObservableObject + @Published + UserDefaults inline     │       │
│   └─────────────────────────────────────────────────────────┘       │
│                                                                      │
│   Problems:                                                          │
│   • No protocols = can't test, can't swap implementations            │
│   • No separation = can't run transcription remotely                 │
│   • Singletons everywhere = hard to inject dependencies              │
│   • ObservableObject = unnecessary view re-renders                   │
│   • NotificationCenter overuse = implicit dependencies               │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. Architecture Vision

### Future-Ready Design

The app must be architected so processing can move to a remote server while the client handles only hardware access and UI.

```
┌─────────────────────────────────────────────────────────────────────┐
│                      TARGET ARCHITECTURE                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ┌─────────────────────┐         ┌─────────────────────┐           │
│   │   CLIENT (macOS)    │         │  SERVER (Future)    │           │
│   │                     │         │                     │           │
│   │  KoeAudio           │  ────►  │  KoeTranscription   │           │
│   │  • AVAudioEngine    │  Audio  │  • WhisperKit (now) │           │
│   │  • Microphone       │  Data   │  • Remote API (later)│          │
│   │                     │         │                     │           │
│   │  KoeTextInsertion   │  ◄────  │  KoeStorage         │           │
│   │  • CGEvents         │  Text   │  • History          │           │
│   │  • Clipboard        │         │  • Settings         │           │
│   │                     │         │                     │           │
│   │  KoeUI              │         └─────────────────────┘           │
│   │  • SwiftUI Views    │                                           │
│   │  • Menu Bar         │         Protocol Boundary                 │
│   │  • Overlays         │         ─────────────────────             │
│   │                     │         TranscriptionService              │
│   │  KoeHotkey          │         TranscriptionRepository           │
│   │  • Global Shortcuts │         (Can be local OR remote)          │
│   └─────────────────────┘                                           │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Principles

1. **Protocol-First**: Every service has a protocol. Implementations are swappable.
2. **Dependency Injection**: No singletons. Pass dependencies via init or Environment.
3. **@Observable**: Use Swift 5.9+ @Observable macro for better performance.
4. **Clear Layers**: Domain → Services → UI (one-way dependency)
5. **Client-Server Ready**: Transcription and storage can run remotely.

---

## 3. Target Structure

```
Koe/
├── KoeApp/                           # Main app target
│   ├── KoeApp.swift                  # App entry with MenuBarExtra
│   ├── AppDelegate.swift             # Hotkey registration only
│   ├── Dependencies.swift            # DI container setup
│   └── Info.plist
│
└── Packages/
    │
    │  ═══════════════════════════════════════════════════════════
    │  DOMAIN LAYER (Pure Swift - no dependencies)
    │  ═══════════════════════════════════════════════════════════
    │
    ├── KoeDomain/
    │   ├── Package.swift
    │   └── Sources/KoeDomain/
    │       ├── Models/
    │       │   ├── Transcription.swift       # Transcription entry model
    │       │   ├── RecordingState.swift      # idle/recording/processing
    │       │   ├── TranscriptionMode.swift   # vad/realtime
    │       │   ├── KoeModel.swift            # tiny/base/small/medium/large
    │       │   └── Language.swift            # Language codes
    │       │
    │       ├── Protocols/
    │       │   ├── AudioRecordingService.swift    # CLIENT-ONLY
    │       │   ├── TranscriptionService.swift     # SWAPPABLE
    │       │   ├── TextInsertionService.swift     # CLIENT-ONLY
    │       │   ├── TranscriptionRepository.swift  # SWAPPABLE
    │       │   └── HotkeyService.swift            # CLIENT-ONLY
    │       │
    │       └── Errors/
    │           ├── KoeError.swift
    │           ├── AudioError.swift
    │           ├── TranscriptionError.swift
    │           └── TextInsertionError.swift
    │
    ├── KoeCore/
    │   ├── Package.swift
    │   └── Sources/KoeCore/
    │       ├── Logging/
    │       │   └── Logger.swift              # OSLog-based logging
    │       └── Extensions/
    │           └── Date+Extensions.swift
    │
    │  ═══════════════════════════════════════════════════════════
    │  CLIENT LAYER (macOS-specific - hardware access)
    │  ═══════════════════════════════════════════════════════════
    │
    ├── KoeAudio/
    │   ├── Package.swift
    │   └── Sources/KoeAudio/
    │       ├── AVAudioEngineRecorder.swift   # Implements AudioRecordingService
    │       ├── AudioLevelMonitor.swift       # RMS calculation
    │       ├── VADProcessor.swift            # Voice Activity Detection
    │       └── AudioBufferManager.swift      # Thread-safe buffer
    │
    ├── KoeTextInsertion/
    │   ├── Package.swift
    │   └── Sources/KoeTextInsertion/
    │       ├── CGEventsInserter.swift        # Keyboard simulation
    │       ├── ClipboardInserter.swift       # Paste fallback
    │       └── TextInsertionCoordinator.swift # Implements TextInsertionService
    │
    ├── KoeHotkey/
    │   ├── Package.swift
    │   └── Sources/KoeHotkey/
    │       └── HotkeyManager.swift           # Implements HotkeyService
    │
    ├── KoeUI/
    │   ├── Package.swift
    │   └── Sources/KoeUI/
    │       ├── Theme/
    │       │   └── KoeTheme.swift            # Colors, fonts, spacing
    │       ├── Components/
    │       │   ├── MicButton.swift
    │       │   ├── WaveformView.swift
    │       │   ├── TranscriptionCard.swift
    │       │   ├── HistoryChip.swift
    │       │   ├── KeyCap.swift
    │       │   └── ModeToggle.swift
    │       ├── Screens/
    │       │   ├── MainView.swift            # Main content
    │       │   └── SettingsView.swift
    │       ├── Overlays/
    │       │   ├── RecordingOverlay.swift
    │       │   └── OverlayWaveform.swift
    │       └── MenuBar/
    │           ├── MenuBarIcon.swift
    │           └── MenuBarContentView.swift
    │
    │  ═══════════════════════════════════════════════════════════
    │  SERVICE LAYER (Swappable implementations)
    │  ═══════════════════════════════════════════════════════════
    │
    ├── KoeTranscription/
    │   ├── Package.swift
    │   └── Sources/KoeTranscription/
    │       ├── Local/
    │       │   ├── WhisperKitTranscriber.swift  # Implements TranscriptionService
    │       │   ├── ModelManager.swift           # Model loading/caching
    │       │   └── ModelDownloader.swift        # Download progress
    │       └── Remote/
    │           └── RemoteTranscriber.swift      # Future: API client
    │
    └── KoeStorage/
        ├── Package.swift
        └── Sources/KoeStorage/
            ├── Local/
            │   ├── UserDefaultsRepository.swift # Implements TranscriptionRepository
            │   └── SettingsStore.swift          # App settings
            └── Remote/
                └── RemoteRepository.swift       # Future: API client
```

---

## Phase 1: Domain Layer

### Goal
Create pure Swift protocols and models with zero dependencies. This is the foundation everything else builds on.

### Files to Create

#### `KoeDomain/Sources/KoeDomain/Models/RecordingState.swift`
```swift
public enum RecordingState: Equatable, Sendable {
    case idle
    case recording
    case processing
}
```

#### `KoeDomain/Sources/KoeDomain/Models/TranscriptionMode.swift`
```swift
public enum TranscriptionMode: String, Codable, Sendable, CaseIterable {
    case vad = "vad"           // On-release (transcribe when key released)
    case realtime = "realtime" // While-speaking (transcribe continuously)

    public var displayName: String {
        switch self {
        case .vad: return "on release"
        case .realtime: return "while speaking"
        }
    }

    public var description: String {
        switch self {
        case .vad: return "types after you release the key"
        case .realtime: return "types as you speak"
        }
    }
}
```

#### `KoeDomain/Sources/KoeDomain/Models/KoeModel.swift`
```swift
public enum KoeModel: String, Codable, Sendable, CaseIterable {
    case tiny = "tiny"
    case base = "base"
    case small = "small"
    case medium = "medium"
    case largeV3 = "large-v3"

    public var displayName: String {
        switch self {
        case .tiny: return "Tiny (39 MB) - Fastest"
        case .base: return "Base (74 MB) - Fast"
        case .small: return "Small (244 MB) - Balanced"
        case .medium: return "Medium (769 MB) - Accurate"
        case .largeV3: return "Large V3 (1.5 GB) - Best Quality"
        }
    }

    public var shortName: String {
        switch self {
        case .tiny: return "Tiny - Fastest"
        case .base: return "Base - Fast"
        case .small: return "Small - Balanced"
        case .medium: return "Medium - Accurate"
        case .largeV3: return "Large - Best"
        }
    }
}
```

#### `KoeDomain/Sources/KoeDomain/Models/Language.swift`
```swift
public struct Language: Codable, Sendable, Equatable, Hashable {
    public let code: String
    public let name: String
    public let flag: String

    public init(code: String, name: String, flag: String) {
        self.code = code
        self.name = name
        self.flag = flag
    }

    public static let auto = Language(code: "auto", name: "Auto-detect", flag: "🌐")
    public static let english = Language(code: "en", name: "English", flag: "🇺🇸")
    public static let spanish = Language(code: "es", name: "Spanish", flag: "🇪🇸")
    public static let portuguese = Language(code: "pt", name: "Portuguese", flag: "🇧🇷")
    public static let french = Language(code: "fr", name: "French", flag: "🇫🇷")
    public static let german = Language(code: "de", name: "German", flag: "🇩🇪")
    public static let italian = Language(code: "it", name: "Italian", flag: "🇮🇹")
    public static let japanese = Language(code: "ja", name: "Japanese", flag: "🇯🇵")
    public static let korean = Language(code: "ko", name: "Korean", flag: "🇰🇷")
    public static let chinese = Language(code: "zh", name: "Chinese", flag: "🇨🇳")

    public static let all: [Language] = [
        .auto, .english, .spanish, .portuguese, .french,
        .german, .italian, .japanese, .korean, .chinese
    ]

    public var isAuto: Bool { code == "auto" }
}
```

#### `KoeDomain/Sources/KoeDomain/Models/Transcription.swift`
```swift
import Foundation

public struct Transcription: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let text: String
    public let duration: TimeInterval
    public let timestamp: Date
    public let language: Language?
    public let model: KoeModel?

    public init(
        id: UUID = UUID(),
        text: String,
        duration: TimeInterval,
        timestamp: Date = Date(),
        language: Language? = nil,
        model: KoeModel? = nil
    ) {
        self.id = id
        self.text = text
        self.duration = duration
        self.timestamp = timestamp
        self.language = language
        self.model = model
    }
}
```

#### `KoeDomain/Sources/KoeDomain/Protocols/AudioRecordingService.swift`
```swift
import Foundation

/// Audio recording service - MUST run on client (hardware access)
public protocol AudioRecordingService: Sendable {
    /// Current audio level (0.0 - 1.0) for visualization
    var audioLevel: Float { get async }

    /// Whether currently recording
    var isRecording: Bool { get async }

    /// Start recording audio
    func startRecording() async throws

    /// Stop recording and return audio data
    func stopRecording() async throws -> Data

    /// Get accumulated audio samples (for streaming transcription)
    func getAudioSamples() async -> [Float]

    /// Audio level stream for real-time updates
    func audioLevelStream() -> AsyncStream<Float>
}
```

#### `KoeDomain/Sources/KoeDomain/Protocols/TranscriptionService.swift`
```swift
import Foundation

/// Transcription service - CAN run locally or remotely
public protocol TranscriptionService: Sendable {
    /// Whether model is loaded and ready
    var isReady: Bool { get async }

    /// Model loading progress (0.0 - 1.0)
    var loadingProgress: Double { get async }

    /// Currently loaded model name
    var currentModel: KoeModel? { get async }

    /// Load a transcription model
    func loadModel(_ model: KoeModel) async throws

    /// Unload current model
    func unloadModel() async

    /// Transcribe audio data
    func transcribe(
        audioData: Data,
        language: Language?
    ) async throws -> Transcription

    /// Transcribe audio from samples (for streaming)
    func transcribe(
        samples: [Float],
        sampleRate: Double,
        language: Language?
    ) async throws -> String

    /// Progress stream for model loading
    func loadingProgressStream() -> AsyncStream<Double>
}
```

#### `KoeDomain/Sources/KoeDomain/Protocols/TextInsertionService.swift`
```swift
import Foundation

/// Text insertion service - MUST run on client (accessibility)
public protocol TextInsertionService: Sendable {
    /// Insert text at current cursor position
    func insertText(_ text: String) async throws

    /// Check if accessibility permission is granted
    func hasPermission() -> Bool

    /// Request accessibility permission
    func requestPermission()
}
```

#### `KoeDomain/Sources/KoeDomain/Protocols/TranscriptionRepository.swift`
```swift
import Foundation

/// Transcription storage - CAN run locally or remotely
public protocol TranscriptionRepository: Sendable {
    /// Save a transcription
    func save(_ transcription: Transcription) async throws

    /// Fetch recent transcriptions
    func fetchRecent(limit: Int) async throws -> [Transcription]

    /// Delete a transcription by ID
    func delete(id: UUID) async throws

    /// Clear all transcriptions
    func clear() async throws

    /// Count of stored transcriptions
    func count() async throws -> Int
}
```

#### `KoeDomain/Sources/KoeDomain/Protocols/HotkeyService.swift`
```swift
import Foundation

/// Hotkey service - MUST run on client
public protocol HotkeyService: Sendable {
    /// Register hotkey handlers
    func register(
        onKeyDown: @escaping @Sendable () -> Void,
        onKeyUp: @escaping @Sendable () -> Void
    )

    /// Unregister hotkey
    func unregister()
}
```

#### `KoeDomain/Sources/KoeDomain/Errors/KoeError.swift`
```swift
import Foundation

public protocol KoeError: LocalizedError, Sendable {}
```

#### `KoeDomain/Sources/KoeDomain/Errors/AudioError.swift`
```swift
import Foundation

public enum AudioError: KoeError {
    case microphoneAccessDenied
    case engineStartFailed(underlying: Error)
    case recordingFailed(underlying: Error)
    case noAudioData
    case audioTooShort(duration: TimeInterval, minimum: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .microphoneAccessDenied:
            return "Microphone access denied. Please enable in System Settings."
        case .engineStartFailed(let error):
            return "Failed to start audio engine: \(error.localizedDescription)"
        case .recordingFailed(let error):
            return "Recording failed: \(error.localizedDescription)"
        case .noAudioData:
            return "No audio data recorded"
        case .audioTooShort(let duration, let minimum):
            return "Audio too short (\(String(format: "%.1f", duration))s). Minimum: \(String(format: "%.1f", minimum))s"
        }
    }
}
```

#### `KoeDomain/Sources/KoeDomain/Errors/TranscriptionError.swift`
```swift
import Foundation

public enum TranscriptionError: KoeError {
    case modelNotLoaded
    case modelLoadFailed(model: KoeModel, underlying: Error)
    case transcriptionFailed(underlying: Error)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Transcription model not loaded"
        case .modelLoadFailed(let model, let error):
            return "Failed to load \(model.displayName): \(error.localizedDescription)"
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        case .cancelled:
            return "Transcription cancelled"
        }
    }
}
```

#### `KoeDomain/Sources/KoeDomain/Errors/TextInsertionError.swift`
```swift
import Foundation

public enum TextInsertionError: KoeError {
    case accessibilityDenied
    case insertionFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .accessibilityDenied:
            return "Accessibility access denied. Please enable in System Settings."
        case .insertionFailed(let error):
            return "Text insertion failed: \(error.localizedDescription)"
        }
    }
}
```

---

## Phase 2: @Observable Migration

### Goal
Replace `ObservableObject` + `@Published` with `@Observable` macro for better SwiftUI performance.

### Current (`AppState.swift`)
```swift
@MainActor
class AppState: ObservableObject {
    static let shared = AppState()  // ❌ Singleton

    @Published var recordingState: RecordingState = .idle
    @Published var currentTranscription: String = ""
    @Published var transcriptionHistory: [TranscriptionEntry] = []
    @Published var isModelLoaded: Bool = false
    // ...
}
```

### Target (`AppState.swift`)
```swift
import SwiftUI
import KoeDomain

@Observable
@MainActor
public final class AppState {
    // Recording
    public var recordingState: RecordingState = .idle
    public var audioLevel: Float = 0.0
    public var currentTranscription: String = ""

    // Model
    public var isModelLoaded: Bool = false
    public var modelLoadingProgress: Double = 0.0
    public var currentModel: KoeModel = .tiny

    // Settings (persisted)
    public var selectedLanguage: Language = .auto
    public var transcriptionMode: TranscriptionMode = .vad

    // History (from repository)
    public var transcriptionHistory: [Transcription] = []

    // Error handling
    public var errorMessage: String?

    // Dependencies (injected)
    private let repository: TranscriptionRepository

    public init(repository: TranscriptionRepository) {
        self.repository = repository
        Task { await loadHistory() }
    }

    // MARK: - History Management

    public func addTranscription(_ transcription: Transcription) async {
        transcriptionHistory.insert(transcription, at: 0)
        if transcriptionHistory.count > 50 {
            transcriptionHistory = Array(transcriptionHistory.prefix(50))
        }
        try? await repository.save(transcription)
    }

    public func clearHistory() async {
        transcriptionHistory.removeAll()
        try? await repository.clear()
    }

    private func loadHistory() async {
        do {
            transcriptionHistory = try await repository.fetchRecent(limit: 50)
        } catch {
            print("Failed to load history: \(error)")
        }
    }
}
```

### View Changes

**Before:**
```swift
struct ContentView: View {
    @EnvironmentObject var appState: AppState  // ❌ Old pattern
    @ObservedObject private var recordingService = RecordingService.shared  // ❌ Singleton
```

**After:**
```swift
struct ContentView: View {
    @Environment(AppState.self) private var appState  // ✅ New pattern
    @Environment(RecordingCoordinator.self) private var coordinator  // ✅ Injected
```

---

## Phase 3: Service Extraction

### Goal
Split the monolithic `RecordingService.swift` (635 lines) into focused, testable services.

### Current Structure
```
RecordingService.swift (635 lines)
├── Audio capture (AVAudioEngine)
├── Audio level monitoring
├── VAD (Voice Activity Detection)
├── Transcription coordination
├── Text insertion (CGEvents + Clipboard)
└── State management
```

### Target Structure

#### `KoeAudio/AVAudioEngineRecorder.swift`
Handles ONLY audio capture:
```swift
import AVFoundation
import KoeDomain

public actor AVAudioEngineRecorder: AudioRecordingService {
    private var audioEngine: AVAudioEngine?
    private var audioBuffer: AudioBufferManager
    private let levelMonitor: AudioLevelMonitor

    private(set) public var isRecording = false

    public var audioLevel: Float {
        get async { await levelMonitor.currentLevel }
    }

    public init() {
        self.audioBuffer = AudioBufferManager()
        self.levelMonitor = AudioLevelMonitor()
    }

    public func startRecording() async throws {
        // Setup AVAudioEngine
        // Install tap on input node
        // Convert to 16kHz mono
    }

    public func stopRecording() async throws -> Data {
        // Stop engine
        // Return WAV data
    }

    public func getAudioSamples() async -> [Float] {
        await audioBuffer.getSamples()
    }

    public func audioLevelStream() -> AsyncStream<Float> {
        levelMonitor.stream()
    }
}
```

#### `KoeAudio/VADProcessor.swift`
Voice Activity Detection:
```swift
public struct VADProcessor: Sendable {
    public let silenceThreshold: Float
    public let silenceDuration: TimeInterval
    public let minSpeechDuration: TimeInterval

    public init(
        silenceThreshold: Float = 0.012,
        silenceDuration: TimeInterval = 1.2,
        minSpeechDuration: TimeInterval = 0.5
    ) {
        self.silenceThreshold = silenceThreshold
        self.silenceDuration = silenceDuration
        self.minSpeechDuration = minSpeechDuration
    }

    public func detectSpeechEnd(
        samples: [Float],
        sampleRate: Double,
        currentSilenceStart: Date?
    ) -> VADResult {
        // Calculate RMS
        // Check against threshold
        // Return speech/silence state
    }
}

public enum VADResult: Sendable {
    case speaking
    case silence(startedAt: Date)
    case speechEnded(samples: [Float])
}
```

#### `KoeTextInsertion/TextInsertionCoordinator.swift`
Text typing:
```swift
import ApplicationServices
import AppKit
import KoeDomain

public final class TextInsertionCoordinator: TextInsertionService {
    private let cgEventsInserter: CGEventsInserter
    private let clipboardInserter: ClipboardInserter

    public init() {
        self.cgEventsInserter = CGEventsInserter()
        self.clipboardInserter = ClipboardInserter()
    }

    public func insertText(_ text: String) async throws {
        // Try CGEvents first (more natural)
        // Fall back to clipboard if needed
    }

    public func hasPermission() -> Bool {
        AXIsProcessTrusted()
    }

    public func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
```

#### `KoeApp/RecordingCoordinator.swift`
Orchestrates the recording flow:
```swift
import SwiftUI
import KoeDomain
import KoeAudio
import KoeTranscription
import KoeTextInsertion

@Observable
@MainActor
public final class RecordingCoordinator {
    // Dependencies (injected)
    private let audioService: AudioRecordingService
    private let transcriptionService: TranscriptionService
    private let textInsertionService: TextInsertionService
    private let vadProcessor: VADProcessor

    // State
    private(set) public var isRecording = false
    private(set) public var audioLevel: Float = 0.0

    // Callbacks
    public var onTranscription: ((String) -> Void)?
    public var onStateChange: ((RecordingState) -> Void)?

    public init(
        audioService: AudioRecordingService,
        transcriptionService: TranscriptionService,
        textInsertionService: TextInsertionService,
        vadProcessor: VADProcessor = VADProcessor()
    ) {
        self.audioService = audioService
        self.transcriptionService = transcriptionService
        self.textInsertionService = textInsertionService
        self.vadProcessor = vadProcessor
    }

    public func startRecording(mode: TranscriptionMode, language: Language) async {
        // Verify model is loaded
        // Start audio recording
        // Start audio level monitoring
        // If realtime mode, start streaming transcription
    }

    public func stopRecording() async {
        // Stop recording
        // Final transcription
        // Insert text
    }
}
```

---

## Phase 4: Storage Layer

### Goal
Abstract storage behind protocols for future remote sync.

#### `KoeStorage/Local/UserDefaultsRepository.swift`
```swift
import Foundation
import KoeDomain

public final class UserDefaultsRepository: TranscriptionRepository {
    private let defaults: UserDefaults
    private let key = "koe_transcription_history"
    private let maxAge: TimeInterval = 7 * 24 * 60 * 60  // 7 days

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func save(_ transcription: Transcription) async throws {
        var history = try await fetchRecent(limit: 100)
        history.insert(transcription, at: 0)

        // Keep only last 50
        if history.count > 50 {
            history = Array(history.prefix(50))
        }

        let data = try JSONEncoder().encode(history)
        defaults.set(data, forKey: key)
    }

    public func fetchRecent(limit: Int) async throws -> [Transcription] {
        guard let data = defaults.data(forKey: key) else { return [] }
        var history = try JSONDecoder().decode([Transcription].self, from: data)

        // Filter out old entries
        let cutoff = Date().addingTimeInterval(-maxAge)
        history = history.filter { $0.timestamp > cutoff }

        return Array(history.prefix(limit))
    }

    public func delete(id: UUID) async throws {
        var history = try await fetchRecent(limit: 100)
        history.removeAll { $0.id == id }
        let data = try JSONEncoder().encode(history)
        defaults.set(data, forKey: key)
    }

    public func clear() async throws {
        defaults.removeObject(forKey: key)
    }

    public func count() async throws -> Int {
        try await fetchRecent(limit: 1000).count
    }
}
```

#### `KoeStorage/Local/SettingsStore.swift`
```swift
import Foundation
import KoeDomain

@Observable
public final class SettingsStore {
    @ObservationIgnored
    private let defaults: UserDefaults

    public var selectedModel: KoeModel {
        didSet { defaults.set(selectedModel.rawValue, forKey: "koe_selected_model") }
    }

    public var selectedLanguage: Language {
        didSet {
            let data = try? JSONEncoder().encode(selectedLanguage)
            defaults.set(data, forKey: "koe_selected_language")
        }
    }

    public var transcriptionMode: TranscriptionMode {
        didSet { defaults.set(transcriptionMode.rawValue, forKey: "koe_transcription_mode") }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Load saved values
        if let modelRaw = defaults.string(forKey: "koe_selected_model"),
           let model = KoeModel(rawValue: modelRaw) {
            self.selectedModel = model
        } else {
            self.selectedModel = .tiny
        }

        if let langData = defaults.data(forKey: "koe_selected_language"),
           let lang = try? JSONDecoder().decode(Language.self, from: langData) {
            self.selectedLanguage = lang
        } else {
            self.selectedLanguage = .auto
        }

        if let modeRaw = defaults.string(forKey: "koe_transcription_mode"),
           let mode = TranscriptionMode(rawValue: modeRaw) {
            self.transcriptionMode = mode
        } else {
            self.transcriptionMode = .vad
        }
    }
}
```

---

## Phase 5: UI Refactoring

### Goal
Extract UI components, use proper theming, remove singletons.

#### `KoeUI/Theme/KoeTheme.swift`
```swift
import SwiftUI

public enum KoeTheme {
    // Colors - Japanese-inspired palette
    public static let background = Color(red: 0.97, green: 0.96, blue: 0.94)  // Washi paper
    public static let accent = Color(red: 0.24, green: 0.30, blue: 0.46)       // Indigo
    public static let textPrimary = Color(red: 0.20, green: 0.20, blue: 0.22)
    public static let textSecondary = Color(red: 0.60, green: 0.58, blue: 0.56)
    public static let textTertiary = Color(red: 0.70, green: 0.68, blue: 0.66)
    public static let surface = Color.white
    public static let surfaceAlt = Color(red: 0.92, green: 0.91, blue: 0.89)

    // Recording states
    public static let recording = Color.red.opacity(0.9)
    public static let processing = accent
    public static let idle = Color.white

    // Spacing
    public static let spacingXS: CGFloat = 4
    public static let spacingSM: CGFloat = 8
    public static let spacingMD: CGFloat = 16
    public static let spacingLG: CGFloat = 24
    public static let spacingXL: CGFloat = 32

    // Corner radius
    public static let radiusSM: CGFloat = 4
    public static let radiusMD: CGFloat = 8
    public static let radiusLG: CGFloat = 16
    public static let radiusFull: CGFloat = 9999
}
```

#### Component Example: `KoeUI/Components/MicButton.swift`
```swift
import SwiftUI
import KoeDomain

public struct MicButton: View {
    let state: RecordingState
    let audioLevel: Float
    let action: () -> Void

    public init(state: RecordingState, audioLevel: Float, action: @escaping () -> Void) {
        self.state = state
        self.audioLevel = audioLevel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                // Outer ring - audio visualization
                if state == .recording {
                    Circle()
                        .stroke(KoeTheme.accent.opacity(0.3), lineWidth: 2)
                        .frame(width: 140 + CGFloat(audioLevel) * 40,
                               height: 140 + CGFloat(audioLevel) * 40)
                        .animation(.easeOut(duration: 0.1), value: audioLevel)
                }

                // Main circle
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 120, height: 120)
                    .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 8)

                // Inner content
                innerContent
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3), value: state)
    }

    @ViewBuilder
    private var innerContent: some View {
        switch state {
        case .idle:
            Image(systemName: "mic.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(KoeTheme.accent)

        case .recording:
            WaveformView(audioLevel: audioLevel, color: .white)
                .frame(width: 60, height: 40)

        case .processing:
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .idle: return KoeTheme.idle
        case .recording: return KoeTheme.recording
        case .processing: return KoeTheme.processing
        }
    }
}
```

---

## Phase 6: Menu Bar Modernization

### Goal
Replace manual NSStatusItem with SwiftUI's `MenuBarExtra`.

### Current (`WhisperApp.swift`)
```swift
// 500+ lines of AppDelegate with manual NSStatusItem
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    // Manual menu creation
    // Manual icon rendering
    // Timer-based animation
}
```

### Target (`KoeApp.swift`)
```swift
import SwiftUI
import KoeDomain
import KoeUI

@main
struct KoeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState: AppState
    @State private var settings: SettingsStore
    @State private var coordinator: RecordingCoordinator

    init() {
        let repository = UserDefaultsRepository()
        let settings = SettingsStore()
        let appState = AppState(repository: repository)

        // Create services
        let audioService = AVAudioEngineRecorder()
        let transcriptionService = WhisperKitTranscriber()
        let textInsertionService = TextInsertionCoordinator()

        let coordinator = RecordingCoordinator(
            audioService: audioService,
            transcriptionService: transcriptionService,
            textInsertionService: textInsertionService
        )

        _appState = State(initialValue: appState)
        _settings = State(initialValue: settings)
        _coordinator = State(initialValue: coordinator)
    }

    var body: some Scene {
        // Main window
        WindowGroup {
            MainView()
                .environment(appState)
                .environment(settings)
                .environment(coordinator)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 380, height: 520)

        // Menu bar
        MenuBarExtra {
            MenuBarContentView()
                .environment(appState)
                .environment(settings)
        } label: {
            MenuBarIcon(
                state: appState.recordingState,
                isModelLoaded: appState.isModelLoaded,
                loadingProgress: appState.modelLoadingProgress,
                language: settings.selectedLanguage
            )
        }
        .menuBarExtraStyle(.window)

        // Settings
        Settings {
            SettingsView()
                .environment(appState)
                .environment(settings)
        }
    }
}

// Minimal AppDelegate - only for hotkey registration
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hotkey registration happens in RecordingCoordinator now
    }
}
```

---

## Phase 7: Testing

### Goal
Add unit tests for all services.

#### Example: `KoeTranscriptionTests/WhisperKitTranscriberTests.swift`
```swift
import Testing
import KoeDomain
@testable import KoeTranscription

@Suite("WhisperKit Transcriber Tests")
struct WhisperKitTranscriberTests {

    @Test("Loads model successfully")
    func loadsModel() async throws {
        let transcriber = WhisperKitTranscriber()

        try await transcriber.loadModel(.tiny)

        let isReady = await transcriber.isReady
        #expect(isReady == true)
    }

    @Test("Throws error when transcribing without model")
    func throwsWithoutModel() async {
        let transcriber = WhisperKitTranscriber()

        await #expect(throws: TranscriptionError.modelNotLoaded) {
            try await transcriber.transcribe(samples: [], sampleRate: 16000, language: nil)
        }
    }
}
```

#### Mock for Testing: `Tests/Mocks/MockTranscriptionService.swift`
```swift
import KoeDomain

public actor MockTranscriptionService: TranscriptionService {
    public var isReady: Bool = false
    public var loadingProgress: Double = 0
    public var currentModel: KoeModel? = nil

    public var transcribeResult: String = "Mock transcription"
    public var shouldThrow: Error? = nil

    public func loadModel(_ model: KoeModel) async throws {
        currentModel = model
        isReady = true
        loadingProgress = 1.0
    }

    public func unloadModel() async {
        currentModel = nil
        isReady = false
    }

    public func transcribe(audioData: Data, language: Language?) async throws -> Transcription {
        if let error = shouldThrow { throw error }
        return Transcription(text: transcribeResult, duration: 1.0)
    }

    public func transcribe(samples: [Float], sampleRate: Double, language: Language?) async throws -> String {
        if let error = shouldThrow { throw error }
        return transcribeResult
    }

    public func loadingProgressStream() -> AsyncStream<Double> {
        AsyncStream { continuation in
            continuation.yield(loadingProgress)
            continuation.finish()
        }
    }
}
```

---

## Phase 8: Naming & Cleanup

### Goal
Rename everything from Whisper → Koe.

### Files to Rename
| Old Name | New Name |
|----------|----------|
| `WhisperApp/` | `KoeApp/` |
| `WhisperApp.swift` | `KoeApp.swift` |
| `WhisperApp.entitlements` | `KoeApp.entitlements` |
| References to "Whisper" | "Koe" |
| References to "WhisperKit" | Keep (it's the library name) |

### String Replacements
```
"Whisper Voice-to-Text" → "Koe 声"
"WhisperApp" → "KoeApp" (folder/target names)
"Whisper model" → "Transcription model"
"Open Whisper" → "Open Koe"
"Quit Whisper" → "Quit Koe"
```

### Keep As-Is
- `WhisperKit` (external library)
- `whisperKit` (variable names referring to WhisperKit)

---

## File-by-File Migration Guide

### Migration Order

| Order | File | Action | Depends On |
|-------|------|--------|------------|
| 1 | Create `Packages/KoeDomain/` | New | - |
| 2 | Create `Packages/KoeCore/` | New | KoeDomain |
| 3 | `AppState.swift` | Refactor to @Observable | KoeDomain |
| 4 | Create `Packages/KoeAudio/` | Extract from RecordingService | KoeDomain |
| 5 | Create `Packages/KoeTextInsertion/` | Extract from RecordingService | KoeDomain |
| 6 | Create `Packages/KoeTranscription/` | Extract from TranscriberService | KoeDomain |
| 7 | Create `Packages/KoeStorage/` | Extract from AppState | KoeDomain |
| 8 | `RecordingService.swift` | Delete (replaced by coordinator) | Steps 4-6 |
| 9 | `TranscriberService.swift` | Delete (replaced by KoeTranscription) | Step 6 |
| 10 | `HotkeyManager.swift` | Move to KoeHotkey package | KoeDomain |
| 11 | Create `Packages/KoeUI/` | Extract components | KoeDomain |
| 12 | `ContentView.swift` | Refactor to use extracted components | KoeUI |
| 13 | `RecordingOverlay.swift` | Move to KoeUI | KoeUI |
| 14 | `SettingsView.swift` | Move to KoeUI, use @Observable | KoeUI |
| 15 | `WhisperApp.swift` | Rewrite with MenuBarExtra | All above |
| 16 | Rename `WhisperApp/` → `KoeApp/` | Final | All above |
| 17 | Create test targets | New | All above |

---

## Summary

### Before → After

| Aspect | Before | After |
|--------|--------|-------|
| **Architecture** | Monolithic, singletons | Modular, DI |
| **State** | ObservableObject | @Observable |
| **Services** | 1 file (635 lines) | 4 packages |
| **Testing** | None | Full coverage |
| **Menu Bar** | Manual NSStatusItem | SwiftUI MenuBarExtra |
| **Protocols** | None | Every service |
| **Remote-Ready** | No | Yes (protocol boundaries) |
| **Name** | Whisper | Koe (声) |

### Benefits

1. **Testable**: Every service has a protocol, can be mocked
2. **Scalable**: Add features without touching existing code
3. **Remote-Ready**: Swap local → remote transcription easily
4. **Maintainable**: Small, focused files
5. **Modern**: Latest Swift patterns (@Observable, async/await, actors)
6. **Fast**: Better SwiftUI performance with @Observable
