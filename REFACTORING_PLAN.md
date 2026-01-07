# Koe (声) App Refactoring Plan

> **Koe** (声) means "voice" in Japanese. This is a privacy-first, on-device voice-to-text application for macOS.

## Architecture Vision: Client-Server Ready

**Key Design Principle**: The app must be architected so that in the future, processing can move to a separate server while the client handles only UI and hardware interactions.

### Client (macOS App) - Always Local
- **Audio Recording** - Microphone access requires local hardware
- **Text Insertion** - Accessibility/CGEvents requires local system access
- **UI/UX** - SwiftUI views, overlays, menu bar
- **Hotkey Handling** - Global keyboard shortcuts

### Server (Future Remote) - Can Be Local or Remote
- **Transcription Processing** - WhisperKit locally OR API remotely
- **Model Management** - Download, load, inference
- **Storage/Database** - History, settings persistence
- **User Preferences** - Sync across devices

### Protocol-Based Abstraction
All server-side services will be defined as protocols, allowing:
```swift
// Local implementation (current)
let transcriber: TranscriptionService = WhisperKitTranscriber()

// Remote implementation (future)
let transcriber: TranscriptionService = RemoteAPITranscriber(baseURL: "http://homeserver:8080")
```

---

## Research Summary: Modern Swift/macOS Architecture Best Practices (2025)

Based on comprehensive research of the latest Swift development practices, here are the key findings and recommendations for building a scalable, maintainable macOS application.

---

## Part 1: Research Findings

### 1.1 Architecture Patterns Comparison

| Pattern | Best For | Pros | Cons |
|---------|----------|------|------|
| **MVVM** | Medium-large apps | Balance of testability & simplicity | Can become bloated with many ViewModels |
| **TCA (Composable Architecture)** | Complex state management | Unidirectional flow, composable, highly testable | Steep learning curve, 3rd party dependency, performance overhead |
| **MV Pattern** | Simple SwiftUI apps | Minimal boilerplate, views as ViewModels | Less separation for complex apps |
| **Clean Architecture** | Enterprise/large scale | Maximum separation, highly testable | More boilerplate, more layers |

**2025 Recommendation**: For a growing app like Whisper, **MVVM with Clean Architecture principles** is the sweet spot. It provides:
- Clear separation of concerns
- Easy to test
- Scalable without over-engineering
- Familiar to most Swift developers

Sources:
- [The Ultimate Guide to Modern iOS Architecture in 2025](https://medium.com/@csmax/the-ultimate-guide-to-modern-ios-architecture-in-2025-9f0d5fdc892f)
- [MVVM vs TCA Comparison](https://www.aleksasimic.com/post/mvvm-vs-tca)
- [SwiftUI Design Patterns Best Practices](https://medium.com/@gongati/swiftui-design-patterns-best-practices-and-architectures-2d5123c9560f)

---

### 1.2 @Observable Macro (Swift 5.9+)

**Key Change**: Replace `ObservableObject` + `@Published` with `@Observable` macro.

**Benefits**:
- **Performance**: Views only re-render when properties they actually read change (not all `@Published` properties)
- **Simpler code**: No need for `@Published`, `@StateObject`, `@ObservedObject`
- **Better tracking**: Works with optionals and collections

**Migration**:
```swift
// OLD (ObservableObject)
class AppState: ObservableObject {
    @Published var isRecording = false
    @Published var transcription = ""
}

// NEW (@Observable)
@Observable
class AppState {
    var isRecording = false
    var transcription = ""
}
```

**Property Wrapper Changes**:
- `@StateObject` → `@State`
- `@ObservedObject` → Remove (just pass the object)
- `@EnvironmentObject` → `@Environment`

Sources:
- [Apple Migration Guide](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro)
- [@Observable Macro Performance](https://www.avanderlee.com/swiftui/observable-macro-performance-increase-observableobject/)

---

### 1.3 Swift 6.2 Concurrency (2025)

**Key Change**: Embrace `@MainActor` by default for app targets.

**New Approach**:
```swift
// App target: MainActor by default
// Use @concurrent for background work

@concurrent
func transcribeAudio(url: URL) async throws -> String {
    // Runs in background
}

// MainActor runs by default
func updateUI(text: String) {
    // Runs on main thread automatically
}
```

**Actor Isolation Guidelines**:
- App code: `@MainActor` by default (enable in build settings)
- SPM packages: Keep `nonisolated` by default
- Use `@concurrent` for heavy operations (transcription, audio processing)
- Use custom `actor` types for shared state that needs isolation

Sources:
- [Swift 6.2 Approachable Concurrency](https://www.avanderlee.com/concurrency/approachable-concurrency-in-swift-6-2-a-clear-guide/)
- [WWDC25 Embracing Swift Concurrency](https://developer.apple.com/videos/play/wwdc2025/268/)

---

### 1.4 Modular Architecture with SPM

**Key Principle**: Break the app into independent Swift packages.

**Recommended Module Structure** (Client-Server Ready):
```
Koe/
├── App/                              # Main app target (thin shell)
│   └── KoeApp.swift
│
├── Packages/
│   │
│   │  ═══════════════════════════════════════════════════
│   │  CLIENT-SIDE PACKAGES (Always run on macOS client)
│   │  ═══════════════════════════════════════════════════
│   │
│   ├── KoeAudio/                     # Audio capture (MUST be local)
│   │   ├── AudioRecorder.swift       # AVAudioEngine microphone
│   │   ├── AudioLevelMonitor.swift   # Real-time levels for UI
│   │   └── AudioBuffer.swift         # Buffer management
│   │
│   ├── KoeTextInsertion/             # Text typing (MUST be local)
│   │   ├── CGEventsInserter.swift    # Keyboard event simulation
│   │   ├── ClipboardInserter.swift   # Paste fallback
│   │   └── TextInsertionCoordinator.swift
│   │
│   ├── KoeHotkey/                    # Global hotkeys (MUST be local)
│   │   └── HotkeyManager.swift
│   │
│   ├── KoeUI/                        # UI components (MUST be local)
│   │   ├── Components/
│   │   ├── Overlays/
│   │   └── MenuBar/
│   │
│   │  ═══════════════════════════════════════════════════
│   │  SHARED PACKAGES (Domain layer - no implementation)
│   │  ═══════════════════════════════════════════════════
│   │
│   ├── KoeDomain/                    # Protocols & Models (shared)
│   │   ├── Models/
│   │   │   ├── Transcription.swift
│   │   │   ├── KoeModel.swift        # tiny/base/small/etc
│   │   │   └── Language.swift
│   │   ├── Protocols/
│   │   │   ├── TranscriptionService.swift   # <- Can be local OR remote
│   │   │   ├── TranscriptionRepository.swift # <- Can be local OR remote
│   │   │   ├── AudioRecordingService.swift  # <- Always local
│   │   │   └── TextInsertionService.swift   # <- Always local
│   │   └── Errors/
│   │
│   ├── KoeCore/                      # Shared utilities
│   │   ├── Extensions/
│   │   ├── Logging/
│   │   └── Networking/               # For future remote API
│   │
│   │  ═══════════════════════════════════════════════════
│   │  SERVER-SIDE PACKAGES (Can run locally OR remotely)
│   │  ═══════════════════════════════════════════════════
│   │
│   ├── KoeTranscription/             # Transcription (swappable)
│   │   ├── Local/
│   │   │   └── WhisperKitService.swift    # Local WhisperKit
│   │   └── Remote/
│   │       └── RemoteTranscriptionService.swift  # Future API client
│   │
│   └── KoeStorage/                   # Persistence (swappable)
│       ├── Local/
│       │   └── UserDefaultsRepository.swift
│       └── Remote/
│           └── RemoteRepository.swift  # Future API client
```

**Benefits**:
- Faster incremental builds (only changed modules recompile)
- Clear boundaries between components
- Independent testing
- Team parallelization
- Reusability across targets

Sources:
- [Modularizing iOS Applications with SwiftUI and SPM](https://nimblehq.co/blog/modern-approach-modularize-ios-swiftui-spm)
- [Microapps Architecture in Swift](https://swiftwithmajid.com/2022/01/12/microapps-architecture-in-swift-spm-basics/)

---

### 1.5 Dependency Injection

**Recommended Approach**: Constructor Injection + SwiftUI Environment

**Pattern**:
```swift
// 1. Define protocols for all services
protocol TranscriptionServiceProtocol: Sendable {
    func transcribe(audio: URL) async throws -> String
}

// 2. Implement concrete types
final class TranscriptionService: TranscriptionServiceProtocol {
    func transcribe(audio: URL) async throws -> String { ... }
}

// 3. Inject via initializer
@Observable
class RecordingViewModel {
    private let transcriptionService: TranscriptionServiceProtocol

    init(transcriptionService: TranscriptionServiceProtocol) {
        self.transcriptionService = transcriptionService
    }
}

// 4. Use Environment for SwiftUI integration
extension EnvironmentValues {
    @Entry var transcriptionService: TranscriptionServiceProtocol = TranscriptionService()
}
```

**For Testing**:
```swift
class MockTranscriptionService: TranscriptionServiceProtocol {
    func transcribe(audio: URL) async throws -> String {
        return "Mock transcription"
    }
}
```

Sources:
- [Dependency Injection in Swift 2025](https://medium.com/@varunbhola1991/dependency-injection-in-swift-2025-clean-architecture-better-testing-7228f971446c)
- [Modern DI for Swift Applications](https://lucasvandongen.dev/dependency_injection_swift_swiftui.php)

---

### 1.6 Repository Pattern

**Purpose**: Abstract data access from business logic.

```swift
// Protocol defines interface
protocol TranscriptionRepository {
    func save(_ transcription: Transcription) async throws
    func fetchRecent(limit: Int) async throws -> [Transcription]
    func delete(id: UUID) async throws
}

// Implementations can vary
final class UserDefaultsTranscriptionRepository: TranscriptionRepository { ... }
final class CoreDataTranscriptionRepository: TranscriptionRepository { ... }
final class InMemoryTranscriptionRepository: TranscriptionRepository { ... } // For tests
```

Sources:
- [Repository Pattern in Swift](https://www.avanderlee.com/swift/repository-design-pattern/)
- [Implementing Repository Pattern](https://medium.com/@asrafulalam2010502cse/implementing-the-repository-pattern-in-swift-32b1534691a4)

---

### 1.7 Error Handling

**Modern Approach**: Use `async throws` with typed errors.

```swift
// Define domain-specific errors
enum TranscriptionError: Error, LocalizedError {
    case modelNotLoaded
    case audioTooShort(duration: TimeInterval)
    case transcriptionFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Whisper model not loaded"
        case .audioTooShort(let duration):
            return "Audio too short: \(duration)s (minimum 0.5s)"
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        }
    }
}

// Use async throws (not Result for new code)
func transcribe(audio: URL) async throws(TranscriptionError) -> String {
    guard modelLoaded else { throw .modelNotLoaded }
    // ...
}
```

Sources:
- [Error Handling in Modern Swift](https://commitstudiogs.medium.com/error-handling-in-modern-swift-async-throws-and-result-explained-c80179936dd8)
- [Swift.org Error Handling](https://docs.swift.org/swift-book/LanguageGuide/ErrorHandling.html)

---

### 1.8 Testing Strategy

**Framework Choice**: Migrate to Swift Testing for new tests.

```swift
import Testing

@Suite("TranscriptionService Tests")
struct TranscriptionServiceTests {

    @Test("Transcribes audio successfully")
    func transcribesAudio() async throws {
        let service = TranscriptionService(model: .tiny)
        let result = try await service.transcribe(audio: testAudioURL)
        #expect(!result.isEmpty)
    }

    @Test("Throws error for empty audio", arguments: [0.0, 0.1, 0.3])
    func throwsForShortAudio(duration: TimeInterval) async {
        let service = TranscriptionService(model: .tiny)
        await #expect(throws: TranscriptionError.audioTooShort) {
            try await service.transcribe(audio: shortAudioURL(duration))
        }
    }
}
```

**Testing Pyramid**:
1. **Unit Tests**: Services, ViewModels, Repositories (fast, many)
2. **Integration Tests**: Service + Repository combinations
3. **UI Tests**: Critical user flows only (slow, few)

Sources:
- [Apple Swift Testing](https://developer.apple.com/xcode/swift-testing)
- [Modern Unit Testing in Swift 2025](https://enricopiovesan.com/modern-unit-testing-in-swift-d633bc47fcd3)

---

### 1.9 macOS Menu Bar Best Practices

**Modern Approach**: Use `MenuBarExtra` (SwiftUI native).

```swift
@main
struct WhisperApp: App {
    var body: some Scene {
        // Main window (hidden by default)
        WindowGroup {
            ContentView()
        }

        // Menu bar item
        MenuBarExtra {
            MenuBarView()
        } label: {
            MenuBarIcon()
        }
        .menuBarExtraStyle(.window) // or .menu for simple dropdown

        // Settings
        Settings {
            SettingsView()
        }
    }
}
```

**Key Points**:
- Set `Application is agent (UIElement) = YES` in Info.plist
- Provide quit option in menu bar UI
- Use `.menuBarExtraStyle(.window)` for rich UI

Sources:
- [Build a macOS Menu Bar Utility in SwiftUI](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/)
- [Using SwiftUI for Modern macOS Menu Bar App](https://kyan.com/news/using-swift-swiftui-to-build-a-modern-macos-menu-bar-app)

---

## Part 2: Current Codebase Analysis

### What You Have Now

| Component | File | Current State |
|-----------|------|---------------|
| **State Management** | `AppState.swift` | `ObservableObject` + `@Published` |
| **Recording** | `RecordingService.swift` | Monolithic (audio + VAD + transcription + typing) |
| **Transcription** | `TranscriberService.swift` | Direct WhisperKit coupling |
| **Hotkey** | `HotkeyManager.swift` | Clean, single responsibility |
| **UI** | `ContentView.swift` | Large file with many components |
| **Menu Bar** | `WhisperApp.swift` | AppDelegate-based, manual NSStatusItem |
| **History** | `AppState.swift` | UserDefaults storage inline |
| **Audio** | `AudioRecorder.swift` | Separate but underutilized |

### Issues Identified

1. **No clear layer separation** - Business logic mixed with UI concerns
2. **Monolithic RecordingService** - 600+ lines handling too many responsibilities
3. **No protocols/interfaces** - Hard to test, tightly coupled
4. **ObservableObject** - Causes unnecessary re-renders
5. **No dependency injection** - Services create their own dependencies
6. **No error handling strategy** - Mixed approaches, silent failures
7. **No tests** - No test files in the project
8. **Manual menu bar** - Not using modern MenuBarExtra

---

## Part 3: Refactoring Plan

### Phase 1: Foundation (Core Architecture)

#### 1.1 Create Module Structure

```
Koe/
├── KoeApp/                        # Thin app shell (main target)
│   ├── KoeApp.swift               # App entry, Scene composition
│   ├── AppDelegate.swift          # Hotkey registration only
│   ├── Dependencies.swift         # DI container / Environment setup
│   └── Info.plist
│
├── Packages/
│   │
│   │  ══════════════════════════════════════════════════════════
│   │  DOMAIN LAYER (Pure Swift, no dependencies, shared models)
│   │  ══════════════════════════════════════════════════════════
│   │
│   ├── KoeDomain/                 # Business models & protocols
│   │   ├── Models/
│   │   │   ├── Transcription.swift
│   │   │   ├── RecordingState.swift
│   │   │   ├── KoeModel.swift         # Model sizes (tiny/base/etc)
│   │   │   └── Language.swift
│   │   ├── Protocols/
│   │   │   ├── AudioRecordingService.swift   # Client-only
│   │   │   ├── TranscriptionService.swift    # Swappable (local/remote)
│   │   │   ├── TextInsertionService.swift    # Client-only
│   │   │   ├── TranscriptionRepository.swift # Swappable (local/remote)
│   │   │   └── HotkeyService.swift           # Client-only
│   │   └── Errors/
│   │       ├── KoeError.swift         # Base error protocol
│   │       ├── AudioError.swift
│   │       ├── TranscriptionError.swift
│   │       └── TextInsertionError.swift
│   │
│   ├── KoeCore/                   # Shared utilities
│   │   ├── Extensions/
│   │   │   └── Date+Extensions.swift
│   │   ├── Logging/
│   │   │   └── Logger.swift       # OSLog wrappers
│   │   └── Networking/
│   │       └── APIClient.swift    # Future remote API client
│   │
│   │  ══════════════════════════════════════════════════════════
│   │  CLIENT LAYER (macOS-specific, hardware access)
│   │  ══════════════════════════════════════════════════════════
│   │
│   ├── KoeAudio/                  # Audio capture & processing
│   │   ├── AVAudioEngineRecorder.swift
│   │   ├── AudioLevelMonitor.swift
│   │   ├── VADProcessor.swift
│   │   └── AudioBufferManager.swift
│   │
│   ├── KoeTextInsertion/          # Text typing/pasting
│   │   ├── CGEventsInserter.swift
│   │   ├── ClipboardInserter.swift
│   │   └── TextInsertionCoordinator.swift
│   │
│   ├── KoeHotkey/                 # Global hotkeys
│   │   └── HotkeyManager.swift
│   │
│   ├── KoeUI/                     # Reusable UI components
│   │   ├── Components/
│   │   │   ├── WaveformView.swift
│   │   │   ├── MicButton.swift
│   │   │   ├── TranscriptionCard.swift
│   │   │   └── HistoryChip.swift
│   │   ├── Overlays/
│   │   │   └── RecordingOverlay.swift
│   │   └── MenuBar/
│   │       ├── MenuBarIcon.swift
│   │       └── MenuBarContentView.swift
│   │
│   │  ══════════════════════════════════════════════════════════
│   │  SERVICE LAYER (Swappable implementations - local or remote)
│   │  ══════════════════════════════════════════════════════════
│   │
│   ├── KoeTranscription/          # Transcription implementations
│   │   ├── Local/
│   │   │   ├── WhisperKitService.swift
│   │   │   ├── ModelManager.swift
│   │   │   └── ModelDownloader.swift
│   │   └── Remote/
│   │       └── RemoteTranscriptionService.swift  # Future
│   │
│   └── KoeStorage/                # Persistence implementations
│       ├── Local/
│       │   ├── UserDefaultsRepository.swift
│       │   └── SettingsManager.swift
│       └── Remote/
│           └── RemoteRepository.swift  # Future
```

**Files to create/modify**:
- [ ] Create `Packages/` directory structure
- [ ] Create `Package.swift` for each module
- [ ] Move existing code into appropriate modules
- [ ] Update main app to import modules
- [ ] Rename all `Whisper*` references to `Koe*`

---

#### 1.2 Migrate to @Observable

**Current** (`AppState.swift`):
```swift
class AppState: ObservableObject {
    @Published var recordingState: RecordingState = .idle
    @Published var currentTranscription: String = ""
    // ...
}
```

**Target**:
```swift
@Observable
final class AppState {
    var recordingState: RecordingState = .idle
    var currentTranscription: String = ""
    // ...
}
```

**Files to modify**:
- [ ] `AppState.swift` - Replace ObservableObject with @Observable
- [ ] `ContentView.swift` - Replace @StateObject/@ObservedObject with @State
- [ ] `SettingsView.swift` - Update property wrappers
- [ ] `RecordingOverlay.swift` - Update property wrappers

---

#### 1.3 Define Domain Protocols

**Create protocols for all services**:

```swift
// WhisperDomain/Protocols/AudioRecordingService.swift
public protocol AudioRecordingService: Sendable {
    var audioLevel: Float { get }
    var isRecording: Bool { get }

    func startRecording() async throws
    func stopRecording() async throws -> URL
}

// WhisperDomain/Protocols/TranscriptionService.swift
public protocol TranscriptionService: Sendable {
    var isModelLoaded: Bool { get }
    var loadingProgress: Double { get }

    func loadModel(_ model: WhisperModel) async throws
    func transcribe(audioURL: URL, language: Language?) async throws -> Transcription
}

// WhisperDomain/Protocols/TextInsertionService.swift
public protocol TextInsertionService: Sendable {
    func insertText(_ text: String) async throws
}

// WhisperDomain/Protocols/TranscriptionRepository.swift
public protocol TranscriptionRepository: Sendable {
    func save(_ transcription: Transcription) async throws
    func fetchRecent(limit: Int) async throws -> [Transcription]
    func delete(id: UUID) async throws
    func clear() async throws
}
```

**Files to create**:
- [ ] `WhisperDomain/Protocols/AudioRecordingService.swift`
- [ ] `WhisperDomain/Protocols/TranscriptionService.swift`
- [ ] `WhisperDomain/Protocols/TextInsertionService.swift`
- [ ] `WhisperDomain/Protocols/TranscriptionRepository.swift`
- [ ] `WhisperDomain/Protocols/HotkeyService.swift`

---

### Phase 2: Service Extraction

#### 2.1 Split RecordingService

**Current**: One 600+ line monolithic service handling:
- Audio capture (AVAudioEngine)
- Audio level monitoring
- VAD (Voice Activity Detection)
- Transcription coordination
- Text insertion

**Target**: Split into focused services:

```swift
// WhisperAudio/AudioRecorder.swift
@concurrent
final class AVAudioEngineRecorder: AudioRecordingService {
    private let engine = AVAudioEngine()
    private var audioBuffer: [Float] = []

    func startRecording() async throws { ... }
    func stopRecording() async throws -> URL { ... }
}

// WhisperAudio/VADProcessor.swift
@concurrent
final class VADProcessor {
    private let silenceThreshold: Float
    private let silenceDuration: TimeInterval

    func detectSpeechEnd(samples: [Float]) -> Bool { ... }
}

// New coordinator that uses injected services
@Observable
@MainActor
final class RecordingCoordinator {
    private let audioService: AudioRecordingService
    private let transcriptionService: TranscriptionService
    private let textInsertionService: TextInsertionService
    private let vadProcessor: VADProcessor

    var state: RecordingState = .idle
    var audioLevel: Float = 0

    init(
        audioService: AudioRecordingService,
        transcriptionService: TranscriptionService,
        textInsertionService: TextInsertionService,
        vadProcessor: VADProcessor
    ) {
        self.audioService = audioService
        self.transcriptionService = transcriptionService
        self.textInsertionService = textInsertionService
        self.vadProcessor = vadProcessor
    }

    func startRecording() async { ... }
    func stopRecording() async { ... }
}
```

**Files to modify/create**:
- [ ] Extract audio capture to `WhisperAudio/AudioRecorder.swift`
- [ ] Extract VAD logic to `WhisperAudio/VADProcessor.swift`
- [ ] Extract audio level monitoring to `WhisperAudio/AudioLevelMonitor.swift`
- [ ] Create `RecordingCoordinator.swift` as thin orchestrator
- [ ] Delete/archive old `RecordingService.swift`

---

#### 2.2 Refactor TranscriberService

**Current**: Direct WhisperKit usage, model loading mixed with transcription.

**Target**: Separate concerns.

```swift
// WhisperTranscription/ModelManager.swift
@concurrent
final class WhisperModelManager {
    private var whisperKit: WhisperKit?

    var loadingProgress: Double = 0
    var isLoaded: Bool { whisperKit != nil }

    func loadModel(_ model: WhisperModel) async throws { ... }
    func unloadModel() { ... }
}

// WhisperTranscription/WhisperKitService.swift
@concurrent
final class WhisperKitTranscriptionService: TranscriptionService {
    private let modelManager: WhisperModelManager

    func transcribe(audioURL: URL, language: Language?) async throws -> Transcription {
        guard modelManager.isLoaded else {
            throw TranscriptionError.modelNotLoaded
        }
        // ...
    }
}
```

**Files to modify/create**:
- [ ] Create `WhisperTranscription/ModelManager.swift`
- [ ] Refactor `TranscriberService.swift` → `WhisperKitService.swift`
- [ ] Create `WhisperTranscription/ModelDownloader.swift` for download logic

---

#### 2.3 Extract Text Insertion

**Current**: Text insertion logic embedded in RecordingService.

**Target**: Dedicated service with strategy pattern.

```swift
// WhisperTextInsertion/TextInsertionCoordinator.swift
@concurrent
final class TextInsertionCoordinator: TextInsertionService {
    private let cgEventsInserter: CGEventsInserter
    private let clipboardInserter: ClipboardInserter

    func insertText(_ text: String) async throws {
        do {
            try await cgEventsInserter.insert(text)
        } catch {
            // Fallback to clipboard
            try await clipboardInserter.insert(text)
        }
    }
}

// WhisperTextInsertion/CGEventsInserter.swift
@concurrent
final class CGEventsInserter {
    func insert(_ text: String) async throws { ... }
}

// WhisperTextInsertion/ClipboardInserter.swift
@concurrent
final class ClipboardInserter {
    func insert(_ text: String) async throws { ... }
}
```

**Files to create**:
- [ ] `WhisperTextInsertion/CGEventsInserter.swift`
- [ ] `WhisperTextInsertion/ClipboardInserter.swift`
- [ ] `WhisperTextInsertion/TextInsertionCoordinator.swift`

---

### Phase 3: Storage & Repository

#### 3.1 Extract History Management

**Current**: History stored in AppState via UserDefaults.

**Target**: Repository pattern with protocol.

```swift
// WhisperDomain/Models/Transcription.swift
public struct Transcription: Identifiable, Codable, Sendable {
    public let id: UUID
    public let text: String
    public let language: Language?
    public let duration: TimeInterval
    public let createdAt: Date
    public let model: WhisperModel
}

// WhisperStorage/UserDefaultsRepository.swift
final class UserDefaultsTranscriptionRepository: TranscriptionRepository {
    private let defaults: UserDefaults
    private let key = "transcription_history"

    func save(_ transcription: Transcription) async throws { ... }
    func fetchRecent(limit: Int) async throws -> [Transcription] { ... }
    func delete(id: UUID) async throws { ... }
    func clear() async throws { ... }
}
```

**Files to create**:
- [ ] `WhisperDomain/Models/Transcription.swift`
- [ ] `WhisperStorage/UserDefaultsRepository.swift`
- [ ] `WhisperStorage/SettingsManager.swift`

---

### Phase 4: UI Refactoring

#### 4.1 Split ContentView

**Current**: Large file with MicButton, WaveformView, StatusText, etc.

**Target**: Extract reusable components to WhisperUI package.

```swift
// WhisperUI/Components/MicButton.swift
public struct MicButton: View {
    let state: RecordingState
    let audioLevel: Float
    let action: () -> Void

    public var body: some View { ... }
}

// WhisperUI/Components/WaveformView.swift
public struct WaveformView: View {
    let audioLevel: Float
    let barCount: Int

    public var body: some View { ... }
}
```

**Files to create/modify**:
- [ ] Extract `MicButton` to `WhisperUI/Components/MicButton.swift`
- [ ] Extract `WaveformView` to `WhisperUI/Components/WaveformView.swift`
- [ ] Extract `TranscriptionCard` to `WhisperUI/Components/TranscriptionCard.swift`
- [ ] Extract `HistoryChip` to `WhisperUI/Components/HistoryChip.swift`
- [ ] Simplify `ContentView.swift` to compose extracted components

---

#### 4.2 Modernize Menu Bar

**Current**: Manual NSStatusItem via AppDelegate.

**Target**: SwiftUI MenuBarExtra.

```swift
// WhisperApp.swift
@main
struct WhisperApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .defaultSize(width: 320, height: 480)

        MenuBarExtra {
            MenuBarContentView()
                .environment(appState)
        } label: {
            MenuBarIcon(state: appState.recordingState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
```

**Files to modify**:
- [ ] Refactor `WhisperApp.swift` to use MenuBarExtra
- [ ] Move menu bar icon to `WhisperUI/MenuBar/MenuBarIcon.swift`
- [ ] Create `WhisperUI/MenuBar/MenuBarContentView.swift`
- [ ] Remove NSStatusItem code from AppDelegate

---

### Phase 5: Error Handling & Logging

#### 5.1 Unified Error Types

```swift
// WhisperDomain/Errors/AudioError.swift
public enum AudioError: Error, LocalizedError {
    case microphoneAccessDenied
    case engineStartFailed(underlying: Error)
    case recordingFailed(underlying: Error)

    public var errorDescription: String? { ... }
}

// WhisperDomain/Errors/TranscriptionError.swift
public enum TranscriptionError: Error, LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(model: WhisperModel, underlying: Error)
    case audioTooShort(duration: TimeInterval, minimum: TimeInterval)
    case transcriptionFailed(underlying: Error)

    public var errorDescription: String? { ... }
}
```

**Files to create**:
- [ ] `WhisperDomain/Errors/AudioError.swift`
- [ ] `WhisperDomain/Errors/TranscriptionError.swift`
- [ ] `WhisperDomain/Errors/TextInsertionError.swift`

---

#### 5.2 Add Logging

```swift
// WhisperCore/Logging/Logger.swift
import OSLog

extension Logger {
    static let audio = Logger(subsystem: "com.whisper", category: "audio")
    static let transcription = Logger(subsystem: "com.whisper", category: "transcription")
    static let ui = Logger(subsystem: "com.whisper", category: "ui")
}

// Usage
Logger.audio.info("Started recording")
Logger.transcription.error("Model load failed: \(error)")
```

**Files to create**:
- [ ] `WhisperCore/Logging/Logger.swift`
- [ ] Add logging calls throughout services

---

### Phase 6: Testing Infrastructure

#### 6.1 Create Test Targets

```
Tests/
├── WhisperAudioTests/
│   ├── AudioRecorderTests.swift
│   └── VADProcessorTests.swift
├── WhisperTranscriptionTests/
│   ├── ModelManagerTests.swift
│   └── TranscriptionServiceTests.swift
├── WhisperStorageTests/
│   └── TranscriptionRepositoryTests.swift
└── WhisperUITests/
    └── RecordingFlowTests.swift
```

#### 6.2 Create Mock Implementations

```swift
// Tests/Mocks/MockTranscriptionService.swift
final class MockTranscriptionService: TranscriptionService {
    var transcribeResult: Result<Transcription, Error> = .success(...)
    var transcribeCallCount = 0

    func transcribe(audioURL: URL, language: Language?) async throws -> Transcription {
        transcribeCallCount += 1
        return try transcribeResult.get()
    }
}
```

**Files to create**:
- [ ] Test targets for each package
- [ ] Mock implementations for all protocols
- [ ] Sample test cases using Swift Testing framework

---

## Part 4: Dependency Injection Setup

### 4.1 Environment-Based DI

```swift
// WhisperApp/Dependencies.swift
extension EnvironmentValues {
    @Entry var audioService: AudioRecordingService = AVAudioEngineRecorder()
    @Entry var transcriptionService: TranscriptionService = WhisperKitTranscriptionService()
    @Entry var textInsertionService: TextInsertionService = TextInsertionCoordinator()
    @Entry var transcriptionRepository: TranscriptionRepository = UserDefaultsTranscriptionRepository()
}

// Usage in views
struct ContentView: View {
    @Environment(\.transcriptionService) private var transcriptionService

    var body: some View { ... }
}
```

### 4.2 Factory Pattern for Complex Objects

```swift
// WhisperApp/ServiceFactory.swift
@MainActor
final class ServiceFactory {
    static let shared = ServiceFactory()

    private init() {}

    func makeRecordingCoordinator() -> RecordingCoordinator {
        RecordingCoordinator(
            audioService: AVAudioEngineRecorder(),
            transcriptionService: WhisperKitTranscriptionService(),
            textInsertionService: TextInsertionCoordinator(),
            vadProcessor: VADProcessor()
        )
    }
}
```

---

## Part 5: Migration Checklist

### Phase 1: Foundation
- [ ] Create package structure
- [ ] Migrate to @Observable
- [ ] Define domain protocols
- [ ] Set up dependency injection

### Phase 2: Service Extraction
- [ ] Split RecordingService into focused services
- [ ] Refactor TranscriberService
- [ ] Extract text insertion logic
- [ ] Create service coordinators

### Phase 3: Storage
- [ ] Create Transcription model
- [ ] Implement TranscriptionRepository
- [ ] Create SettingsManager
- [ ] Migrate existing data

### Phase 4: UI
- [ ] Extract UI components to package
- [ ] Modernize menu bar with MenuBarExtra
- [ ] Update all views to use new services
- [ ] Improve overlay implementation

### Phase 5: Error Handling
- [ ] Define error types
- [ ] Add OSLog logging
- [ ] Add error UI feedback
- [ ] Handle edge cases

### Phase 6: Testing
- [ ] Create test targets
- [ ] Write mock implementations
- [ ] Add unit tests for services
- [ ] Add integration tests

---

## Part 6: Recommended Order of Changes

1. **Start with @Observable migration** - Smallest change, immediate benefit
2. **Create domain protocols** - Foundation for DI
3. **Extract services one at a time** - RecordingService first (biggest)
4. **Add tests as you go** - Test each extracted service
5. **UI refactoring last** - After services are stable
6. **Modularize into packages** - Final step after architecture is proven

---

## References

### Architecture & Patterns
- [The Ultimate Guide to Modern iOS Architecture in 2025](https://medium.com/@csmax/the-ultimate-guide-to-modern-ios-architecture-in-2025-9f0d5fdc892f)
- [SwiftUI Design Patterns Best Practices](https://medium.com/@gongati/swiftui-design-patterns-best-practices-and-architectures-2d5123c9560f)
- [MVVM vs TCA](https://www.aleksasimic.com/post/mvvm-vs-tca)
- [Modularizing iOS Applications with SwiftUI and SPM](https://nimblehq.co/blog/modern-approach-modularize-ios-swiftui-spm)

### Swift 6.2 & Concurrency
- [Swift 6.2 Approachable Concurrency](https://www.avanderlee.com/concurrency/approachable-concurrency-in-swift-6-2-a-clear-guide/)
- [WWDC25 Embracing Swift Concurrency](https://developer.apple.com/videos/play/wwdc2025/268/)
- [MainActor vs GlobalActor Guide 2025](https://gauravtakjaipur.medium.com/swift-concurrency-mainactor-vs-globalactor-in-swift-the-complete-2025-guide-every-ios-c5aab821849f)

### @Observable Macro
- [Apple Migration Guide](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro)
- [@Observable Macro Performance](https://www.avanderlee.com/swiftui/observable-macro-performance-increase-observableobject/)

### Dependency Injection
- [Dependency Injection in Swift 2025](https://medium.com/@varunbhola1991/dependency-injection-in-swift-2025-clean-architecture-better-testing-7228f971446c)
- [Repository Pattern in Swift](https://www.avanderlee.com/swift/repository-design-pattern/)

### Testing
- [Apple Swift Testing](https://developer.apple.com/xcode/swift-testing)
- [Modern Unit Testing in Swift 2025](https://enricopiovesan.com/modern-unit-testing-in-swift-d633bc47fcd3)

### macOS Menu Bar
- [Build a macOS Menu Bar Utility in SwiftUI](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/)
