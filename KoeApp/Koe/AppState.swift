import SwiftUI
import AVFoundation
import ApplicationServices
import KoeDomain
import CoreGraphics

@Observable
@MainActor
public final class AppState {
    // Singleton for backward compatibility during migration
    // Will be removed once DI is fully implemented
    public static let shared = AppState()

    // Recording state
    public var recordingState: RecordingState = .idle {
        didSet {
            NotificationCenter.default.post(name: .appStateChanged, object: nil)
        }
    }

    public var currentTranscription: String = ""
    public var audioLevel: Float = 0.0

    // Model state
    public var isModelLoaded: Bool = false
    public var modelLoadingProgress: Double = 0.0

    // Refinement model state
    public var isRefinementModelLoaded: Bool = false
    public var refinementModelProgress: Double = 0.0

    // Readiness state
    public var appReadinessState: AppReadinessState = .welcome
    public var hasMicrophonePermission: Bool = false
    public var hasAccessibilityPermission: Bool = false
    public var hasScreenRecordingPermission: Bool = false

    // History
    public var transcriptionHistory: [Transcription] = []
    public var processingHistory: [ProcessingResult] = []

    // Error handling
    public var errorMessage: String?

    // Settings - stored in UserDefaults
    @ObservationIgnored
    private var _selectedModel: String {
        get { UserDefaults.standard.string(forKey: "selectedModel") ?? "tiny" }
        set { UserDefaults.standard.set(newValue, forKey: "selectedModel") }
    }

    @ObservationIgnored
    private var _selectedLanguage: String {
        get { UserDefaults.standard.string(forKey: "selectedLanguage") ?? "auto" }
        set { UserDefaults.standard.set(newValue, forKey: "selectedLanguage") }
    }

    @ObservationIgnored
    private var _transcriptionMode: String {
        get { UserDefaults.standard.string(forKey: "transcriptionMode") ?? "vad" }
        set { UserDefaults.standard.set(newValue, forKey: "transcriptionMode") }
    }

    @ObservationIgnored
    private var _isRefinementEnabled: Bool {
        get {
            // Default to true if not set
            if UserDefaults.standard.object(forKey: "isRefinementEnabled") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "isRefinementEnabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "isRefinementEnabled") }
    }

    @ObservationIgnored
    private var _isAutoEnterEnabled: Bool {
        get {
            // Default to false if not set
            return UserDefaults.standard.bool(forKey: "isAutoEnterEnabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "isAutoEnterEnabled") }
    }

    // Public accessors that trigger observation
    public var selectedModel: String {
        get { _selectedModel }
        set { _selectedModel = newValue }
    }

    public var selectedLanguage: String {
        get { _selectedLanguage }
        set { _selectedLanguage = newValue }
    }

    public var transcriptionMode: String {
        get { _transcriptionMode }
        set { _transcriptionMode = newValue }
    }

    public var isRefinementEnabled: Bool {
        get { _isRefinementEnabled }
        set { _isRefinementEnabled = newValue }
    }

    public var isAutoEnterEnabled: Bool {
        get { _isAutoEnterEnabled }
        set { _isAutoEnterEnabled = newValue }
    }

    // Computed properties for typed access
    public var currentKoeModel: KoeModel {
        KoeModel(rawValue: selectedModel) ?? .tiny
    }

    public var currentLanguage: Language {
        Language.all.first { $0.code == selectedLanguage } ?? .auto
    }

    public var currentTranscriptionMode: TranscriptionMode {
        TranscriptionMode(rawValue: transcriptionMode) ?? .vad
    }

    public var hasAllPermissions: Bool {
        hasMicrophonePermission && hasAccessibilityPermission && hasScreenRecordingPermission
    }

    private init() {
        loadHistory()
    }

    // MARK: - Permission Management

    public func checkMicrophonePermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        hasMicrophonePermission = (status == .authorized)
    }

    public func checkAccessibilityPermission() {
        // AXIsProcessTrusted() has caching issues, but the cache is refreshed when
        // the "com.apple.accessibility.api" distributed notification fires
        // (which happens when any app's accessibility permission changes)
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    public func checkScreenRecordingPermission() {
        // Check Screen Recording permission by trying to get window info
        // If permission is not granted, window titles will be nil for user apps
        let options = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            hasScreenRecordingPermission = false
            return
        }

        // System processes that always show window titles even without permission
        let systemProcesses = Set(["Window Server", "Control Center", "Dock", "SystemUIServer"])

        // Check if any NON-SYSTEM window has a name (indicates permission granted)
        for window in windowList {
            guard let ownerName = window[kCGWindowOwnerName as String] as? String else { continue }

            // Skip system processes
            if systemProcesses.contains(ownerName) { continue }

            if let name = window[kCGWindowName as String] as? String, !name.isEmpty {
                hasScreenRecordingPermission = true
                return
            }
        }

        // No user app window names found - permission not granted
        hasScreenRecordingPermission = false
    }

    public func checkAllPermissions() {
        checkMicrophonePermission()
        checkAccessibilityPermission()
        checkScreenRecordingPermission()
    }

    public func advanceReadinessState() {
        switch appReadinessState {
        case .welcome:
            checkAllPermissions()
            appReadinessState = hasAllPermissions ? .loading : .needsPermissions

        case .needsPermissions:
            checkAllPermissions()
            if hasAllPermissions {
                appReadinessState = .loading
            }

        case .loading:
            if isModelLoaded {
                appReadinessState = .ready
                NotificationCenter.default.post(name: .appReady, object: nil)
            }

        case .ready:
            break
        }
    }

    // MARK: - History Management

    public func addTranscription(_ text: String, duration: TimeInterval) {
        let entry = Transcription(
            text: text,
            duration: duration,
            timestamp: Date(),
            language: currentLanguage,
            model: currentKoeModel
        )
        transcriptionHistory.insert(entry, at: 0)

        // Keep only last 50 entries
        if transcriptionHistory.count > 50 {
            transcriptionHistory = Array(transcriptionHistory.prefix(50))
        }

        saveHistory()
    }

    public func clearHistory() {
        transcriptionHistory.removeAll()
        processingHistory.removeAll()
        saveHistory()
    }

    public func addProcessingResult(_ result: ProcessingResult) {
        processingHistory.insert(result, at: 0)

        // Keep only last 50 entries
        if processingHistory.count > 50 {
            processingHistory = Array(processingHistory.prefix(50))
        }

        saveProcessingHistory()
    }

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: "transcriptionHistory"),
           let history = try? JSONDecoder().decode([Transcription].self, from: data) {
            // Filter out entries older than 7 days
            let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
            transcriptionHistory = history.filter { $0.timestamp > cutoff }
        }

        loadProcessingHistory()
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(transcriptionHistory) {
            UserDefaults.standard.set(data, forKey: "transcriptionHistory")
        }
    }

    private func loadProcessingHistory() {
        if let data = UserDefaults.standard.data(forKey: "processingHistory"),
           let history = try? JSONDecoder().decode([ProcessingResult].self, from: data) {
            // Filter out entries older than 7 days
            let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
            processingHistory = history.filter { $0.timestamp > cutoff }
        }
    }

    private func saveProcessingHistory() {
        if let data = try? JSONEncoder().encode(processingHistory) {
            UserDefaults.standard.set(data, forKey: "processingHistory")
        }
    }
}

// MARK: - Legacy Support

/// Backward compatibility alias - will be removed after full migration
typealias TranscriptionEntry = Transcription
