import Foundation

/// Lifecycle state of a pipeline element
public enum ElementState: String, Codable, Sendable {
    case sleeping      // Not initialized, no resources
    case waking        // Loading resources
    case active        // Ready to process
    case processing    // Currently processing
    case idle          // Done, waiting (may auto-sleep)
    case error         // Error state
    case shuttingDown  // Releasing resources
}

/// Sleep mode configuration
public struct SleepConfiguration: Codable, Sendable, Equatable {
    /// Whether sleep mode is enabled
    public var enabled: Bool

    /// Seconds of inactivity before auto-sleeping (0 = never auto-sleep)
    public var autoSleepDelay: TimeInterval

    /// Whether to wake immediately when pipeline starts (pre-warm)
    public var preWarm: Bool

    /// Default: sleep enabled, 60s timeout, no pre-warm
    public static let `default` = SleepConfiguration(
        enabled: true,
        autoSleepDelay: 60.0,
        preWarm: false
    )

    /// Always active, never sleep
    public static let alwaysActive = SleepConfiguration(
        enabled: false,
        autoSleepDelay: 0,
        preWarm: true
    )

    /// Aggressive power saving: sleep after 10s
    public static let powerSaver = SleepConfiguration(
        enabled: true,
        autoSleepDelay: 10.0,
        preWarm: false
    )

    /// Balanced: sleep after 2 minutes
    public static let balanced = SleepConfiguration(
        enabled: true,
        autoSleepDelay: 120.0,
        preWarm: false
    )

    public init(enabled: Bool, autoSleepDelay: TimeInterval, preWarm: Bool) {
        self.enabled = enabled
        self.autoSleepDelay = autoSleepDelay
        self.preWarm = preWarm
    }
}

/// Protocol for elements that support sleep mode
public protocol SleepableElement: PipelineElement {
    /// Current lifecycle state
    var state: ElementState { get }

    /// Sleep configuration
    var sleepConfig: SleepConfiguration { get set }

    /// Wake the element (load model/resources)
    func wake() async throws

    /// Put element to sleep (unload resources)
    func sleep() async

    /// Check if element is ready to process
    var isAwake: Bool { get }
}

public extension SleepableElement {
    var isAwake: Bool {
        state == .active || state == .idle
    }
}

/// Base class providing sleep mode functionality
open class SleepableElementBase: @unchecked Sendable {
    private let stateLock = NSLock()
    private var _state: ElementState = .sleeping
    private var autoSleepTask: Task<Void, Never>?
    private var _sleepConfig: SleepConfiguration = .default
    private var lastActiveTime: Date?

    public var state: ElementState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _state
    }

    public var sleepConfig: SleepConfiguration {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _sleepConfig
        }
        set {
            stateLock.lock()
            _sleepConfig = newValue
            stateLock.unlock()

            // If sleep disabled and currently sleeping, wake up
            if !newValue.enabled && _state == .sleeping {
                Task {
                    try? await ensureAwake()
                }
            }

            // Cancel any pending auto-sleep if disabled
            if !newValue.enabled {
                autoSleepTask?.cancel()
                autoSleepTask = nil
            }
        }
    }

    public init(sleepConfig: SleepConfiguration = .default) {
        self._sleepConfig = sleepConfig

        // If pre-warm enabled and sleep disabled, start active
        if sleepConfig.preWarm && !sleepConfig.enabled {
            _state = .active
        }
    }

    /// Update state thread-safely
    public func setState(_ newState: ElementState) {
        stateLock.lock()
        let oldState = _state
        _state = newState
        let config = _sleepConfig
        stateLock.unlock()

        // Track last active time
        if newState == .processing {
            lastActiveTime = Date()
        }

        // Cancel pending auto-sleep on state change
        autoSleepTask?.cancel()
        autoSleepTask = nil

        // Schedule auto-sleep if enabled and moving to idle
        if config.enabled && config.autoSleepDelay > 0 && newState == .idle {
            scheduleAutoSleep()
        }

        // Notify state change (subclasses can override)
        onStateChanged(from: oldState, to: newState)
    }

    /// Override to handle state changes
    open func onStateChanged(from oldState: ElementState, to newState: ElementState) {
        // Default: no-op
    }

    private func scheduleAutoSleep() {
        let delay = sleepConfig.autoSleepDelay

        autoSleepTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            guard let self = self, !Task.isCancelled else { return }

            self.stateLock.lock()
            let shouldSleep = self._state == .idle && self._sleepConfig.enabled
            self.stateLock.unlock()

            if shouldSleep {
                if let sleepable = self as? (any SleepableElement) {
                    await sleepable.sleep()
                }
            }
        }
    }

    /// Ensure element is awake before processing
    public func ensureAwake() async throws {
        stateLock.lock()
        let currentState = _state
        let config = _sleepConfig
        stateLock.unlock()

        // If sleep is disabled and we're sleeping, treat as needing wake
        if currentState == .sleeping || (currentState == .idle && config.enabled) {
            setState(.waking)

            if let sleepable = self as? (any SleepableElement) {
                try await sleepable.wake()
            }

            setState(.active)
        }
    }

    deinit {
        autoSleepTask?.cancel()
    }
}

/// Resource usage tracking
public struct ResourceUsage: Sendable, Codable {
    public let memoryBytes: Int64
    public let modelLoaded: Bool
    public let gpuMemoryBytes: Int64
    public let lastActiveTime: Date?

    public init(
        memoryBytes: Int64 = 0,
        modelLoaded: Bool = false,
        gpuMemoryBytes: Int64 = 0,
        lastActiveTime: Date? = nil
    ) {
        self.memoryBytes = memoryBytes
        self.modelLoaded = modelLoaded
        self.gpuMemoryBytes = gpuMemoryBytes
        self.lastActiveTime = lastActiveTime
    }

    public var formattedMemory: String {
        formatBytes(memoryBytes)
    }

    public var formattedGPUMemory: String {
        formatBytes(gpuMemoryBytes)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1_000_000 {
            return "\(bytes / 1_000) KB"
        } else if bytes < 1_000_000_000 {
            return String(format: "%.1f MB", Double(bytes) / 1_000_000)
        } else {
            return String(format: "%.2f GB", Double(bytes) / 1_000_000_000)
        }
    }

    public static let zero = ResourceUsage()
}

/// Protocol for elements that track resource usage
public protocol ResourceTrackingElement: PipelineElement {
    var resourceUsage: ResourceUsage { get }
    var estimatedResourceUsage: ResourceUsage { get }
}
