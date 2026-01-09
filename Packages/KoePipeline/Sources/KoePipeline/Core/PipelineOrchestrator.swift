import Foundation

/// Global sleep configuration for all elements
public struct GlobalSleepSettings: Codable, Sendable {
    public var defaultConfig: SleepConfiguration
    public var perElementOverrides: [String: SleepConfiguration]

    public static let `default` = GlobalSleepSettings(
        defaultConfig: .default,
        perElementOverrides: [:]
    )

    public init(defaultConfig: SleepConfiguration, perElementOverrides: [String: SleepConfiguration] = [:]) {
        self.defaultConfig = defaultConfig
        self.perElementOverrides = perElementOverrides
    }

    /// Get sleep config for a specific element
    public func config(for typeId: String) -> SleepConfiguration {
        perElementOverrides[typeId] ?? defaultConfig
    }
}

/// Orchestrates pipeline execution
public actor PipelineOrchestrator {
    // MARK: - Properties

    private var loadedElements: [String: any PipelineElement] = [:]
    private var currentContext: PipelineContext?
    private var isRunning: Bool = false

    /// Global sleep settings
    public var sleepSettings: GlobalSleepSettings = .default

    /// Element configurator - called after each element is created to wire up handlers
    /// Parameters: (element, typeId) - configure the element's handlers based on its type
    public var elementConfigurator: ((any PipelineElement, String) -> Void)?

    // MARK: - Callbacks

    public var onElementStarted: ((String) -> Void)?
    public var onElementCompleted: ((String, TimeInterval) -> Void)?
    public var onElementStateChanged: ((String, ElementState) -> Void)?
    public var onPipelineCompleted: ((PipelineRunSummary) -> Void)?
    public var onError: ((String, Error) -> Void)?
    public var onProgress: ((Double, String) -> Void)?

    // MARK: - Initialization

    public init(sleepSettings: GlobalSleepSettings = .default) {
        self.sleepSettings = sleepSettings
    }

    // MARK: - Validation

    /// Validate a pipeline configuration
    public func validate(_ pipeline: Pipeline) -> PipelineValidationResult {
        var errors: [PipelineValidationError] = []
        var warnings: [String] = []

        // Check for empty pipeline
        let enabledElements = pipeline.enabledElements
        if enabledElements.isEmpty {
            return PipelineValidationResult(isValid: false, errors: [.emptyPipeline])
        }

        // Get element info for validation
        var elementInfoMap: [String: ElementInfo] = [:]
        for instance in enabledElements {
            if let info = ElementRegistry.shared.getAllInfo().first(where: { $0.typeId == instance.typeId }) {
                elementInfoMap[instance.id] = info
            } else {
                errors.append(.missingRequiredElement(typeId: instance.typeId, reason: "Element type not registered"))
            }
        }

        // Check position constraints
        for (index, instance) in enabledElements.enumerated() {
            guard let info = elementInfoMap[instance.id] else { continue }

            // Must be first
            if info.constraints.contains(.mustBeFirst) && index != 0 {
                errors.append(.invalidPosition(typeId: instance.typeId, reason: "Must be first in pipeline"))
            }

            // Must be last
            if info.constraints.contains(.mustBeLast) && index != enabledElements.count - 1 {
                errors.append(.invalidPosition(typeId: instance.typeId, reason: "Must be last in pipeline"))
            }

            // Cannot be first
            if info.constraints.contains(.cannotBeFirst) && index == 0 {
                errors.append(.invalidPosition(typeId: instance.typeId, reason: "Cannot be first in pipeline"))
            }

            // Cannot be last
            if info.constraints.contains(.cannotBeLast) && index == enabledElements.count - 1 {
                errors.append(.invalidPosition(typeId: instance.typeId, reason: "Cannot be last in pipeline"))
            }
        }

        // Check for duplicate elements (where not allowed)
        var seenTypes: Set<String> = []
        for instance in enabledElements {
            guard let info = elementInfoMap[instance.id] else { continue }

            if !info.constraints.contains(.allowMultiple) && seenTypes.contains(instance.typeId) {
                errors.append(.duplicateElement(typeId: instance.typeId))
            }
            seenTypes.insert(instance.typeId)
        }

        // Check data type compatibility
        for i in 0..<(enabledElements.count - 1) {
            let current = enabledElements[i]
            let next = enabledElements[i + 1]

            guard let currentInfo = elementInfoMap[current.id],
                  let nextInfo = elementInfoMap[next.id] else { continue }

            let outputType = currentInfo.connectionRules.producesOutput
            let acceptedTypes = nextInfo.connectionRules.acceptsInput

            if !acceptedTypes.contains(.any) && !acceptedTypes.contains(outputType) {
                errors.append(.incompatibleConnection(
                    from: current.typeId,
                    to: next.typeId,
                    reason: "Output type '\(outputType)' not accepted by next element"
                ))
            }
        }

        // Check required dependencies
        let enabledTypeIds = Set(enabledElements.map { $0.typeId })
        for instance in enabledElements {
            guard let info = elementInfoMap[instance.id] else { continue }

            for required in info.connectionRules.requiredPredecessors {
                if !enabledTypeIds.contains(required) {
                    errors.append(.missingDependency(typeId: instance.typeId, dependsOn: required))
                }
            }
        }

        return PipelineValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }

    // MARK: - Execution

    /// Run a pipeline
    public func run(_ pipeline: Pipeline, initialContext: PipelineContext? = nil) async throws -> PipelineContext {
        guard !isRunning else {
            throw PipelineError.alreadyRunning
        }

        // Validate first
        let validation = validate(pipeline)
        guard validation.isValid else {
            throw PipelineError.validationFailed(validation.errors)
        }

        isRunning = true
        defer { isRunning = false }

        // Create or use provided context
        let context = initialContext ?? PipelineContext()
        currentContext = context

        // Load and prepare elements
        let enabledElements = pipeline.enabledElements
        var elements: [any PipelineElement] = []

        for instance in enabledElements {
            guard let element = ElementRegistry.shared.create(typeId: instance.typeId) else {
                throw PipelineError.elementNotFound(instance.typeId)
            }

            // Apply configuration
            element.configuration = instance.configuration.mapValues { $0.value }
            element.isEnabled = instance.isEnabled

            // Apply sleep configuration if element supports it
            if var sleepableElement = element as? (any SleepableElement) {
                sleepableElement.sleepConfig = sleepSettings.config(for: instance.typeId)
            }

            // Allow app to configure handlers on this element
            elementConfigurator?(element, instance.typeId)

            try await element.prepare()
            elements.append(element)
            loadedElements[instance.id] = element
        }

        // Execute elements in sequence
        let totalElements = Double(elements.count)
        let enabledElementTypes = enabledElements.map { $0.typeId }

        for (index, element) in elements.enumerated() {
            // Check for cancellation
            if context.isCancelled {
                // Record cancelled metrics
                let metrics = ElementExecutionMetrics(
                    elementId: element.id,
                    elementType: enabledElementTypes[index],
                    startTime: Date(),
                    endTime: Date(),
                    status: .cancelled,
                    inputCharCount: context.text.count,
                    outputCharCount: context.text.count
                )
                context.recordMetrics(metrics)
                throw PipelineError.cancelled
            }

            context.currentElementId = element.id

            // Notify progress
            let progress = Double(index) / totalElements
            onProgress?(progress, "Running \(element.displayName)...")
            onElementStarted?(element.id)

            // Capture input state
            let inputText = context.text
            let startTime = Date()
            let startMemory = Self.getCurrentMemoryUsage()

            // Execute element with timing
            var executionStatus: ElementExecutionMetrics.ExecutionStatus = .success
            var errorMessage: String?

            do {
                try await element.process(context)
            } catch {
                executionStatus = .failed
                errorMessage = error.localizedDescription
                onError?(element.id, error)

                // Record failed metrics before throwing
                let endTime = Date()
                let endMemory = Self.getCurrentMemoryUsage()
                let memoryUsed = endMemory > startMemory ? endMemory - startMemory : 0

                let metrics = ElementExecutionMetrics(
                    elementId: element.id,
                    elementType: enabledElementTypes[index],
                    startTime: startTime,
                    endTime: endTime,
                    status: .failed,
                    memoryUsedBytes: memoryUsed,
                    inputCharCount: inputText.count,
                    outputCharCount: context.text.count,
                    errorMessage: errorMessage
                )
                context.recordMetrics(metrics)

                throw PipelineError.elementFailed(element.id, error)
            }

            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)
            let endMemory = Self.getCurrentMemoryUsage()
            let memoryUsed = endMemory > startMemory ? endMemory - startMemory : 0

            // Record timing (legacy)
            context.recordTiming(elementId: element.id, duration: duration)

            // Record detailed metrics
            let metrics = ElementExecutionMetrics(
                elementId: element.id,
                elementType: enabledElementTypes[index],
                startTime: startTime,
                endTime: endTime,
                status: executionStatus,
                memoryUsedBytes: memoryUsed,
                inputCharCount: inputText.count,
                outputCharCount: context.text.count,
                errorMessage: errorMessage
            )
            context.recordMetrics(metrics)

            onElementCompleted?(element.id, duration)
        }

        // Cleanup
        for element in elements {
            await element.cleanup()
        }
        loadedElements.removeAll()

        // Final notification
        onProgress?(1.0, "Complete")
        onPipelineCompleted?(context.summary)

        currentContext = nil
        return context
    }

    /// Cancel the current pipeline run
    public func cancel() {
        currentContext?.isCancelled = true
    }

    /// Check if pipeline is currently running
    public var running: Bool {
        isRunning
    }

    // MARK: - Memory Tracking

    /// Get current process memory usage in bytes
    private static func getCurrentMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            return Int64(info.resident_size)
        }
        return 0
    }
}

/// Pipeline execution errors
public enum PipelineError: Error, LocalizedError {
    case alreadyRunning
    case validationFailed([PipelineValidationError])
    case elementNotFound(String)
    case elementFailed(String, Error)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Pipeline is already running"
        case .validationFailed(let errors):
            return "Pipeline validation failed: \(errors.map { $0.description }.joined(separator: ", "))"
        case .elementNotFound(let id):
            return "Element type '\(id)' not found in registry"
        case .elementFailed(let id, let error):
            return "Element '\(id)' failed: \(error.localizedDescription)"
        case .cancelled:
            return "Pipeline was cancelled"
        }
    }
}
