import AVFoundation
import ApplicationServices
import CoreGraphics
import KoeCommands
import KoeDomain
import KoePipeline
import SwiftUI
import UserNotifications

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

    /// Whether the current recording was triggered by voice command (vs hotkey)
    public var isVoiceCommandTriggered: Bool = false

    public var currentTranscription: String = ""
    public var audioLevel: Float = 0.0

    // Model state
    public var isModelLoaded: Bool = false
    public var modelLoadingProgress: Double = 0.0

    // Background model service for downloading additional models
    @ObservationIgnored
    public lazy var backgroundModelService = BackgroundModelService.shared

    /// Check if a model is available for use
    public func isModelAvailable(_ model: KoeModel) -> Bool {
        backgroundModelService.isModelReady(model)
    }

    /// Models currently available for selection
    public var availableModels: [KoeModel] {
        KoeModel.allCases.filter { isModelAvailable($0) }
    }

    /// Whether background model processing is active
    public var isBackgroundProcessing: Bool {
        backgroundModelService.isProcessing
    }

    // Refinement model state
    public var isRefinementModelLoaded: Bool = false
    public var refinementModelProgress: Double = 0.0

    // Readiness state
    public var appReadinessState: AppReadinessState = .welcome
    public var hasMicrophonePermission: Bool = false
    public var hasAccessibilityPermission: Bool = false
    public var hasScreenRecordingPermission: Bool = false
    public var hasNotificationPermission: Bool = false

    // History
    public var transcriptionHistory: [Transcription] = []
    public var processingHistory: [ProcessingResult] = []

    // Pipeline execution history
    public var pipelineExecutionHistory: [PipelineExecutionRecord] = []

    /// Most recent metrics for each pipeline stage (for quick UI access)
    public var lastStageMetrics: [String: ElementExecutionMetrics] = [:]

    // Error handling
    public var errorMessage: String?

    // WhisperKit uses a single model (turbo) - no selection needed
    // Language is always auto-detect

    // Refinement and AutoEnter use stored properties for proper @Observable tracking
    // Loaded from UserDefaults in init(), saved in didSet

    // Ollama settings
    @ObservationIgnored
    private var _ollamaEndpoint: String {
        get { UserDefaults.standard.string(forKey: "ollamaEndpoint") ?? "http://localhost:11434" }
        set { UserDefaults.standard.set(newValue, forKey: "ollamaEndpoint") }
    }

    @ObservationIgnored
    private var _ollamaModel: String {
        get { UserDefaults.standard.string(forKey: "ollamaModel") ?? "mistral:7b-instruct" }
        set { UserDefaults.standard.set(newValue, forKey: "ollamaModel") }
    }

    @ObservationIgnored
    private var _customRefinementPrompt: String {
        get { UserDefaults.standard.string(forKey: "customRefinementPrompt") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "customRefinementPrompt") }
    }

    // Hotkey settings - stored properties for proper observation
    private var _hotkeyKeyCode: UInt32 = 49 {
        didSet { UserDefaults.standard.set(Int(_hotkeyKeyCode), forKey: "hotkeyKeyCode") }
    }

    private var _hotkeyModifiers: Int = 2 {
        didSet { UserDefaults.standard.set(_hotkeyModifiers, forKey: "hotkeyModifiers") }
    }

    // Stored properties for proper @Observable tracking
    public var isRefinementEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isRefinementEnabled, forKey: "isRefinementEnabled")
        }
    }

    public var isAutoEnterEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isAutoEnterEnabled, forKey: "isAutoEnterEnabled")
        }
    }

    // MARK: - Transcription Engine Selection (mutually exclusive)

    /// Whether WhisperKit transcription is enabled
    /// Default: false (requires model download, enable for higher accuracy)
    public var isWhisperKitEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isWhisperKitEnabled, forKey: "isWhisperKitEnabled")
            // Notify for resource management when disabled
            if !isWhisperKitEnabled {
                NotificationCenter.default.post(name: .transcriptionEngineDisabled, object: "whisperkit")
            }
        }
    }

    /// Whether Apple Speech transcription is enabled
    /// Default: true (instant startup, no download required)
    public var isAppleSpeechEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isAppleSpeechEnabled, forKey: "isAppleSpeechEnabled")
            // Notify for resource management when disabled
            if !isAppleSpeechEnabled {
                NotificationCenter.default.post(name: .transcriptionEngineDisabled, object: "apple-speech")
            }
            // Handle mutual exclusivity
            if isAppleSpeechEnabled {
                isWhisperKitBalancedEnabled = false
                isWhisperKitAccurateEnabled = false
                isWhisperKitEnabled = false
            }
        }
    }

    /// Whether WhisperKit Balanced transcription is enabled
    /// Default: false (requires ~632MB download)
    public var isWhisperKitBalancedEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isWhisperKitBalancedEnabled, forKey: "transcribeWhisperKitBalancedEnabled")
            // Update global WhisperKit flag
            if isWhisperKitBalancedEnabled {
                isWhisperKitEnabled = true
                isAppleSpeechEnabled = false
                isWhisperKitAccurateEnabled = false
            }
        }
    }

    /// Whether WhisperKit Accurate transcription is enabled
    /// Default: false (requires ~947MB download)
    public var isWhisperKitAccurateEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isWhisperKitAccurateEnabled, forKey: "transcribeWhisperKitAccurateEnabled")
            // Update global WhisperKit flag
            if isWhisperKitAccurateEnabled {
                isWhisperKitEnabled = true
                isAppleSpeechEnabled = false
                isWhisperKitBalancedEnabled = false
            }
        }
    }

    /// Whether to copy transcribed text to clipboard when target is lost (user switched apps)
    /// If false, text is simply discarded when target cannot be restored
    public var copyToClipboardOnTargetLost: Bool {
        get { UserDefaults.standard.object(forKey: "copyToClipboardOnTargetLost") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "copyToClipboardOnTargetLost") }
    }

    // Ollama settings
    public var ollamaEndpoint: String {
        get { _ollamaEndpoint }
        set { _ollamaEndpoint = newValue }
    }

    public var ollamaModel: String {
        get { _ollamaModel }
        set { _ollamaModel = newValue }
    }

    public var customRefinementPrompt: String {
        get { _customRefinementPrompt }
        set { _customRefinementPrompt = newValue }
    }

    // Hotkey settings
    public var hotkeyKeyCode: UInt32 {
        get { _hotkeyKeyCode }
        set {
            _hotkeyKeyCode = newValue
            NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
        }
    }

    public var hotkeyModifiers: Int {
        get { _hotkeyModifiers }
        set {
            _hotkeyModifiers = newValue
            NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
        }
    }

    /// Display string for current hotkey
    public var hotkeyDisplayString: String {
        var parts: [String] = []

        if hotkeyModifiers & 4 != 0 { parts.append("⌃") }  // control
        if hotkeyModifiers & 2 != 0 { parts.append("⌥") }  // option
        if hotkeyModifiers & 8 != 0 { parts.append("⇧") }  // shift
        if hotkeyModifiers & 1 != 0 { parts.append("⌘") }  // command

        // Key name
        switch hotkeyKeyCode {
        case 49: parts.append("Space")
        case 36: parts.append("Return")
        case 61: parts.append("R-⌥")  // Right Option key
        case 96: parts.append("F5")
        case 97: parts.append("F6")
        case 98: parts.append("F7")
        default: parts.append("Key\(hotkeyKeyCode)")
        }

        return parts.joined()
    }

    // New combinable refinement options - use stored properties for observation to work
    public var isCleanupEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isCleanupEnabled, forKey: "isCleanupEnabled")
        }
    }

    public var toneStyle: String = "none" {
        didSet {
            UserDefaults.standard.set(toneStyle, forKey: "toneStyle")
        }
    }

    public var isPromptImproverEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isPromptImproverEnabled, forKey: "isPromptImproverEnabled")
        }
    }

    // AI tier - stored property for observation to work
    public var aiTierRaw: String = "best" {
        didSet {
            UserDefaults.standard.set(aiTierRaw, forKey: "aiTier")
        }
    }

    // Ring animation style - stored property for observation to work
    public var ringAnimationStyleRaw: String = "wave" {
        didSet {
            UserDefaults.standard.set(ringAnimationStyleRaw, forKey: "ringAnimationStyle")
        }
    }

    public var currentRingAnimationStyle: RingAnimationStyle {
        get { RingAnimationStyle(rawValue: ringAnimationStyleRaw) ?? .wave }
        set { ringAnimationStyleRaw = newValue.rawValue }
    }

    // Voice Commands settings
    public var isCommandListeningEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isCommandListeningEnabled, forKey: "isCommandListeningEnabled")
            NotificationCenter.default.post(name: .commandListeningChanged, object: nil)
        }
    }

    /// Voice profile - stored property for @Observable tracking
    public var voiceProfile: VoiceProfile? {
        didSet {
            // Sync to VoiceProfileManager when set
            if voiceProfile != oldValue {
                VoiceProfileManager.shared.currentProfile = voiceProfile
            }
        }
    }

    public var hasVoiceProfile: Bool {
        voiceProfile != nil
    }

    /// Voice command settings (experimental features)
    public var voiceCommandSettings: VoiceCommandSettings = .load() {
        didSet {
            voiceCommandSettings.save()
            NotificationCenter.default.post(name: .voiceCommandSettingsChanged, object: nil)
        }
    }

    /// Reload voice profile from storage (call on app launch or after external changes)
    public func reloadVoiceProfile() {
        let loaded = VoiceProfileManager.shared.currentProfile
        voiceProfile = loaded
        print("[AppState] reloadVoiceProfile: loaded=\(loaded != nil), hasProfile=\(hasVoiceProfile)")
    }

    /// Runtime state for Ollama connection (not persisted)
    public var isOllamaConnected: Bool = false

    // WhisperKit uses a single model (turbo)
    public var currentKoeModel: KoeModel {
        .balanced
    }

    // Language is always auto-detect - node handles specific language settings
    public var currentLanguage: Language {
        .auto
    }

    public var currentAITier: AITier {
        get { AITier(rawValue: aiTierRaw) ?? .best }
        set { aiTierRaw = newValue.rawValue }
    }

    public var hasAllPermissions: Bool {
        hasMicrophonePermission && hasAccessibilityPermission && hasScreenRecordingPermission
            && hasNotificationPermission
    }

    private init() {
        loadHistory()
        loadRefinementOptions()
        loadHotkeySettings()
        loadPipelineHistory()
        loadCommandSettings()
    }

    private func loadCommandSettings() {
        // Load voice profile from storage
        reloadVoiceProfile()

        // Load voice command settings
        if UserDefaults.standard.object(forKey: "isCommandListeningEnabled") != nil {
            isCommandListeningEnabled = UserDefaults.standard.bool(forKey: "isCommandListeningEnabled")
        }
    }

    private func loadHotkeySettings() {
        // Load saved hotkey settings
        let savedKeyCode = UserDefaults.standard.integer(forKey: "hotkeyKeyCode")
        if savedKeyCode != 0 {
            _hotkeyKeyCode = UInt32(savedKeyCode)
        }
        if UserDefaults.standard.object(forKey: "hotkeyModifiers") != nil {
            _hotkeyModifiers = UserDefaults.standard.integer(forKey: "hotkeyModifiers")
        }
    }

    private func loadRefinementOptions() {
        // Load toggle states for pipeline nodes
        if UserDefaults.standard.object(forKey: "isRefinementEnabled") != nil {
            isRefinementEnabled = UserDefaults.standard.bool(forKey: "isRefinementEnabled")
        }
        if UserDefaults.standard.object(forKey: "isAutoEnterEnabled") != nil {
            isAutoEnterEnabled = UserDefaults.standard.bool(forKey: "isAutoEnterEnabled")
        }

        // Load transcription engine states (default: Apple Speech enabled)
        if UserDefaults.standard.object(forKey: "isWhisperKitEnabled") != nil {
            isWhisperKitEnabled = UserDefaults.standard.bool(forKey: "isWhisperKitEnabled")
        }
        if UserDefaults.standard.object(forKey: "isAppleSpeechEnabled") != nil {
            isAppleSpeechEnabled = UserDefaults.standard.bool(forKey: "isAppleSpeechEnabled")
        }
        if UserDefaults.standard.object(forKey: "transcribeWhisperKitBalancedEnabled") != nil {
            isWhisperKitBalancedEnabled = UserDefaults.standard.bool(forKey: "transcribeWhisperKitBalancedEnabled")
        }
        if UserDefaults.standard.object(forKey: "transcribeWhisperKitAccurateEnabled") != nil {
            isWhisperKitAccurateEnabled = UserDefaults.standard.bool(forKey: "transcribeWhisperKitAccurateEnabled")
        }

        // Load saved refinement options
        if UserDefaults.standard.object(forKey: "isCleanupEnabled") != nil {
            isCleanupEnabled = UserDefaults.standard.bool(forKey: "isCleanupEnabled")
        }
        if let saved = UserDefaults.standard.string(forKey: "toneStyle") {
            toneStyle = saved
        }
        if UserDefaults.standard.object(forKey: "isPromptImproverEnabled") != nil {
            isPromptImproverEnabled = UserDefaults.standard.bool(forKey: "isPromptImproverEnabled")
        }
        if let savedTier = UserDefaults.standard.string(forKey: "aiTier") {
            aiTierRaw = savedTier
        }
        if let savedAnimStyle = UserDefaults.standard.string(forKey: "ringAnimationStyle") {
            ringAnimationStyleRaw = savedAnimStyle
        }
    }

    // MARK: - Permission Management

    public func checkMicrophonePermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        hasMicrophonePermission = (status == .authorized)
    }

    public func checkAccessibilityPermission() {
        // AXIsProcessTrusted() has caching issues - it may return stale values even after
        // the user grants permission. To work around this, we also try to actually use
        // accessibility APIs and check if they work.

        // First, check the fast path
        if AXIsProcessTrusted() {
            hasAccessibilityPermission = true
            return
        }

        // AXIsProcessTrusted() returned false, but it might be cached.
        // Try to actually use accessibility to verify.
        // If we can get an attribute from the system-wide element, permission is granted.
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &value)

        // If we get a valid result (even if nil), we have permission
        // .cannotComplete means no focused app, but we still have access
        // .apiDisabled or .notImplemented means no permission
        hasAccessibilityPermission = (result == .success || result == .cannotComplete || result == .noValue)
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

    public func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.hasNotificationPermission = (settings.authorizationStatus == .authorized)
            }
        }
    }

    public func checkAllPermissions() {
        checkMicrophonePermission()
        checkAccessibilityPermission()
        checkScreenRecordingPermission()
        checkNotificationPermission()
    }

    public func advanceReadinessState() {
        switch appReadinessState {
        case .welcome:
            checkAllPermissions()
            if hasAllPermissions {
                // Skip loading if Apple Speech is enabled (instant startup)
                if isAppleSpeechEnabled && !isWhisperKitEnabled {
                    isModelLoaded = true
                    appReadinessState = .ready
                    NotificationCenter.default.post(name: .appReady, object: nil)
                } else {
                    appReadinessState = .loading
                }
            } else {
                appReadinessState = .needsPermissions
            }

        case .needsPermissions:
            checkAllPermissions()
            if hasAllPermissions {
                // Skip loading if Apple Speech is enabled (instant startup)
                if isAppleSpeechEnabled && !isWhisperKitEnabled {
                    isModelLoaded = true
                    appReadinessState = .ready
                    NotificationCenter.default.post(name: .appReady, object: nil)
                } else {
                    appReadinessState = .loading
                }
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

    public func addTranscription(
        _ text: String, duration: TimeInterval, wasRefined: Bool = false, originalText: String? = nil,
        refinementSettings: RefinementSettings? = nil, pipelineRunId: UUID? = nil
    ) {
        // Check if any experimental features were used
        let usedExperimental = isWhisperKitEnabled || isCommandListeningEnabled || isAutoEnterEnabled

        let entry = Transcription(
            text: text,
            duration: duration,
            timestamp: Date(),
            language: currentLanguage,
            model: currentKoeModel,
            wasRefined: wasRefined,
            originalText: originalText,
            refinementSettings: refinementSettings,
            pipelineRunId: pipelineRunId,
            isExperimental: usedExperimental
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
            let history = try? JSONDecoder().decode([Transcription].self, from: data)
        {
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
            let history = try? JSONDecoder().decode([ProcessingResult].self, from: data)
        {
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

    // MARK: - Pipeline Execution History

    /// Add a pipeline execution record
    public func addPipelineExecution(_ record: PipelineExecutionRecord) {
        NSLog("[Pipeline Metrics] Adding execution record with %d element metrics", record.elementMetrics.count)

        pipelineExecutionHistory.insert(record, at: 0)

        // Update last stage metrics for quick access
        // Replace whole dictionary to trigger @Observable update
        var newMetrics: [String: ElementExecutionMetrics] = [:]
        for metrics in record.elementMetrics {
            NSLog("[Pipeline Metrics] Recording metric for '%@': %@", metrics.elementType, metrics.formattedDuration)
            newMetrics[metrics.elementType] = metrics
        }
        lastStageMetrics = newMetrics

        // Keep only last 100 executions
        if pipelineExecutionHistory.count > 100 {
            pipelineExecutionHistory = Array(pipelineExecutionHistory.prefix(100))
        }

        savePipelineHistory()
        NSLog("[Pipeline Metrics] Stored %d stage metrics", lastStageMetrics.count)
    }

    /// Get metrics for a specific stage from the last execution
    public func lastMetrics(for stageTypeId: String) -> ElementExecutionMetrics? {
        lastStageMetrics[stageTypeId]
    }

    /// Clear all pipeline execution history
    public func clearPipelineHistory() {
        pipelineExecutionHistory.removeAll()
        lastStageMetrics.removeAll()
        UserDefaults.standard.removeObject(forKey: "pipelineExecutionHistory")
    }

    private func loadPipelineHistory() {
        if let data = UserDefaults.standard.data(forKey: "pipelineExecutionHistory"),
            let history = try? JSONDecoder().decode([PipelineExecutionRecord].self, from: data)
        {
            // Filter out entries older than 7 days
            let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
            pipelineExecutionHistory = history.filter { $0.timestamp > cutoff }

            // Rebuild last stage metrics from most recent execution
            if let latest = pipelineExecutionHistory.first {
                for metrics in latest.elementMetrics {
                    lastStageMetrics[metrics.elementType] = metrics
                }
            }
        }
    }

    private func savePipelineHistory() {
        if let data = try? JSONEncoder().encode(pipelineExecutionHistory) {
            UserDefaults.standard.set(data, forKey: "pipelineExecutionHistory")
        }
    }
}

// MARK: - Legacy Support

/// Backward compatibility alias - will be removed after full migration
typealias TranscriptionEntry = Transcription
