import Foundation
import KoeDomain
import KoeTranscription
import os.log

private let logger = Logger(subsystem: "com.koe.app", category: "WhisperKitLifecycle")

// MARK: - WhisperKit Balanced Lifecycle Handler

/// Manages WhisperKit Balanced model lifecycle (load/unload)
/// Uses the turbo model for good speed/accuracy balance
@MainActor
public final class WhisperKitBalancedLifecycleHandler: NodeLifecycleHandler {
    public static let shared = WhisperKitBalancedLifecycleHandler()

    public let nodeTypeId = NodeTypeId.whisperKitBalanced

    private init() {}

    // MARK: - NodeLifecycleHandler

    public var isLoaded: Bool {
        RecordingCoordinator.shared.isModelLoaded && RecordingCoordinator.shared.currentModel == .balanced
    }

    public func load() async throws {
        logger.info("Loading WhisperKit Balanced model...")

        // Update state flags
        AppState.shared.isWhisperKitEnabled = true
        AppState.shared.isAppleSpeechEnabled = false

        // Load the balanced model
        let model = KoeModel.balanced
        await RecordingCoordinator.shared.loadModel(model)

        logger.info("WhisperKit Balanced model loaded: \(model.rawValue)")
    }

    public func unload() {
        logger.info("Unloading WhisperKit Balanced model...")

        // Update state flag
        AppState.shared.isWhisperKitEnabled = false

        // Unload the model to free memory
        RecordingCoordinator.shared.unloadModel()

        logger.info("WhisperKit Balanced model unloaded")
    }
}

// MARK: - WhisperKit Accurate Lifecycle Handler

/// Manages WhisperKit Accurate model lifecycle (load/unload)
/// Uses the large-v3 model for best accuracy
@MainActor
public final class WhisperKitAccurateLifecycleHandler: NodeLifecycleHandler {
    public static let shared = WhisperKitAccurateLifecycleHandler()

    public let nodeTypeId = NodeTypeId.whisperKitAccurate

    private init() {}

    // MARK: - NodeLifecycleHandler

    public var isLoaded: Bool {
        RecordingCoordinator.shared.isModelLoaded && RecordingCoordinator.shared.currentModel == .accurate
    }

    public func load() async throws {
        logger.info("Loading WhisperKit Accurate model...")

        // Update state flags
        AppState.shared.isWhisperKitEnabled = true
        AppState.shared.isAppleSpeechEnabled = false

        // Load the accurate model
        let model = KoeModel.accurate
        await RecordingCoordinator.shared.loadModel(model)

        logger.info("WhisperKit Accurate model loaded: \(model.rawValue)")
    }

    public func unload() {
        logger.info("Unloading WhisperKit Accurate model...")

        // Update state flag
        AppState.shared.isWhisperKitEnabled = false

        // Unload the model to free memory
        RecordingCoordinator.shared.unloadModel()

        logger.info("WhisperKit Accurate model unloaded")
    }
}

// MARK: - Apple Speech Lifecycle Handler

/// Apple Speech lifecycle handler
/// Apple Speech is lightweight - no heavy resources to manage
/// But we still track state for consistency
@MainActor
public final class AppleSpeechLifecycleHandler: NodeLifecycleHandler {
    public static let shared = AppleSpeechLifecycleHandler()

    public let nodeTypeId = NodeTypeId.appleSpeech

    private init() {}

    // MARK: - NodeLifecycleHandler

    public var isLoaded: Bool {
        AppState.shared.isAppleSpeechEnabled
    }

    public func load() async throws {
        logger.info("Activating Apple Speech...")

        // Update state flags
        AppState.shared.isAppleSpeechEnabled = true
        AppState.shared.isWhisperKitEnabled = false

        // Unload any WhisperKit model to free memory
        RecordingCoordinator.shared.unloadModel()

        // Apple Speech is always ready - no model to load
        logger.info("Apple Speech activated")
    }

    public func unload() {
        logger.info("Deactivating Apple Speech...")

        // Update state flag
        AppState.shared.isAppleSpeechEnabled = false

        // Apple Speech has no heavy resources to unload
        logger.info("Apple Speech deactivated")
    }
}

// MARK: - Registration

/// Register all lifecycle handlers at app startup
@MainActor
public func registerNodeLifecycleHandlers() {
    let registry = NodeLifecycleRegistry.shared

    // Transcription engines
    registry.register(AppleSpeechLifecycleHandler.shared)
    registry.register(WhisperKitBalancedLifecycleHandler.shared)
    registry.register(WhisperKitAccurateLifecycleHandler.shared)
}
