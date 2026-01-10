import Foundation

/// Typing speed presets
public enum TypingSpeed: String, Codable, Sendable, CaseIterable {
    case instant = "instant"  // All at once
    case fast = "fast"  // Very quick typing
    case natural = "natural"  // Human-like speed
    case slow = "slow"  // Deliberate, visible typing

    public var displayName: String {
        switch self {
        case .instant: return "Instant"
        case .fast: return "Fast"
        case .natural: return "Natural"
        case .slow: return "Slow"
        }
    }

    public var description: String {
        switch self {
        case .instant: return "Insert all text at once"
        case .fast: return "Quick typing (~100 WPM)"
        case .natural: return "Human-like (~40 WPM)"
        case .slow: return "Slow and visible (~20 WPM)"
        }
    }

    /// Delay between characters in seconds
    public var characterDelay: TimeInterval {
        switch self {
        case .instant: return 0
        case .fast: return 0.01
        case .natural: return 0.03
        case .slow: return 0.06
        }
    }
}

/// Configuration for Auto Type action
public struct AutoTypeConfig: Codable, Sendable, Equatable {
    public var speed: TypingSpeed
    public var delayBefore: TimeInterval
    public var addTrailingNewline: Bool
    public var clearSelection: Bool

    public static let `default` = AutoTypeConfig(
        speed: .instant,
        delayBefore: 0.1,
        addTrailingNewline: false,
        clearSelection: true
    )

    public init(speed: TypingSpeed, delayBefore: TimeInterval, addTrailingNewline: Bool, clearSelection: Bool) {
        self.speed = speed
        self.delayBefore = delayBefore
        self.addTrailingNewline = addTrailingNewline
        self.clearSelection = clearSelection
    }
}

/// Auto Type action - types text into the active application
public final class AutoTypeAction: PipelineAction, @unchecked Sendable {
    // MARK: - PipelineAction Protocol

    public let actionTypeId = "auto-type"
    public var id: String { actionTypeId }
    public let displayName = "Auto Type"
    public let description = "Type text into active app"
    public let icon = "keyboard"

    public var constraints: ElementConstraints {
        // Note: Removed cannotBeFirst to allow text-only pipelines where this is the first action
        [.optional]
    }

    public var connectionRules: ConnectionRules {
        ConnectionRules(
            acceptsInput: [.text, .richText],
            producesOutput: .text  // Pass through for chaining
        )
    }

    public var isEnabled: Bool = true

    public var configuration: [String: Any] {
        get {
            [
                "speed": config.speed.rawValue,
                "delayBefore": config.delayBefore,
                "addTrailingNewline": config.addTrailingNewline,
                "clearSelection": config.clearSelection,
            ]
        }
        set {
            if let speedRaw = newValue["speed"] as? String,
                let speed = TypingSpeed(rawValue: speedRaw)
            {
                config.speed = speed
            }
            if let v = newValue["delayBefore"] as? TimeInterval { config.delayBefore = v }
            if let v = newValue["addTrailingNewline"] as? Bool { config.addTrailingNewline = v }
            if let v = newValue["clearSelection"] as? Bool { config.clearSelection = v }
        }
    }

    // MARK: - Action-Specific

    public var config: AutoTypeConfig = .default

    /// Handler to type text (injected from app)
    public var typeHandler: ((String, TypingSpeed, Bool) async throws -> Void)?

    /// Handler for instant insert
    public var instantInsertHandler: ((String) async throws -> Void)?

    // MARK: - Initialization

    public init(config: AutoTypeConfig = .default) {
        self.config = config
    }

    // MARK: - Processing

    public func prepare() async throws {}

    public func process(_ context: PipelineContext) async throws {
        guard !context.text.isEmpty else { return }

        var textToType = context.text

        if config.addTrailingNewline && !textToType.hasSuffix("\n") {
            textToType += "\n"
        }

        if config.delayBefore > 0 {
            try await Task.sleep(nanoseconds: UInt64(config.delayBefore * 1_000_000_000))
        }

        if config.speed == .instant {
            if let handler = instantInsertHandler {
                try await handler(textToType)
            } else if let handler = typeHandler {
                try await handler(textToType, .instant, config.clearSelection)
            }
        } else {
            if let handler = typeHandler {
                try await handler(textToType, config.speed, config.clearSelection)
            }
        }

        context.setCustomData(true, forKey: "auto_type_performed")
        context.setCustomData(textToType.count, forKey: "characters_typed")
    }

    public func cleanup() async {}
}

/// Configuration for Auto Enter action
public struct AutoEnterConfig: Codable, Sendable, Equatable {
    public var delayAfterType: TimeInterval
    public var enterCount: Int

    public static let `default` = AutoEnterConfig(
        delayAfterType: 0.1,
        enterCount: 1
    )

    public init(delayAfterType: TimeInterval, enterCount: Int) {
        self.delayAfterType = delayAfterType
        self.enterCount = max(1, enterCount)
    }
}

/// Auto Enter action - presses Enter after typing
public final class AutoEnterAction: PipelineAction, @unchecked Sendable {
    // MARK: - PipelineAction Protocol

    public let actionTypeId = "auto-enter"
    public var id: String { actionTypeId }
    public let displayName = "Auto Enter"
    public let description = "Press Enter after typing"
    public let icon = "return"

    public var constraints: ElementConstraints {
        [.mustBeLast, .optional]
    }

    public var connectionRules: ConnectionRules {
        ConnectionRules(
            acceptsInput: [.text, .richText, .any],
            producesOutput: .text,
            requiredPredecessors: ["auto-type"]
        )
    }

    public var isEnabled: Bool = true

    public var configuration: [String: Any] {
        get {
            [
                "delayAfterType": config.delayAfterType,
                "enterCount": config.enterCount,
            ]
        }
        set {
            if let v = newValue["delayAfterType"] as? TimeInterval { config.delayAfterType = v }
            if let v = newValue["enterCount"] as? Int { config.enterCount = v }
        }
    }

    // MARK: - Action-Specific

    public var config: AutoEnterConfig = .default

    /// Handler to press Enter key (injected from app)
    public var enterHandler: (() async throws -> Void)?

    // MARK: - Initialization

    public init(config: AutoEnterConfig = .default) {
        self.config = config
    }

    // MARK: - Processing

    public func prepare() async throws {}

    public func process(_ context: PipelineContext) async throws {
        let typePerformed: Bool = context.getCustomData(forKey: "auto_type_performed") ?? false
        guard typePerformed else {
            context.warnings.append("Auto-enter skipped: typing not performed")
            return
        }

        if config.delayAfterType > 0 {
            try await Task.sleep(nanoseconds: UInt64(config.delayAfterType * 1_000_000_000))
        }

        if let handler = enterHandler {
            for _ in 0..<config.enterCount {
                try await handler()
            }
        }

        context.setCustomData(true, forKey: "auto_enter_performed")
        context.setCustomData(config.enterCount, forKey: "enter_count")
    }

    public func cleanup() async {}
}

/// Copy to Clipboard action
public final class CopyToClipboardAction: PipelineAction, @unchecked Sendable {
    public let actionTypeId = "copy-clipboard"
    public var id: String { actionTypeId }
    public let displayName = "Copy to Clipboard"
    public let description = "Copy text to clipboard"
    public let icon = "doc.on.clipboard"

    public var constraints: ElementConstraints {
        [.cannotBeFirst, .optional]
    }

    public var connectionRules: ConnectionRules {
        ConnectionRules(
            acceptsInput: [.text, .richText],
            producesOutput: .text
        )
    }

    public var isEnabled: Bool = true
    public var configuration: [String: Any] = [:]

    public var copyHandler: ((String) async throws -> Void)?

    public init() {}

    public func prepare() async throws {}

    public func process(_ context: PipelineContext) async throws {
        guard !context.text.isEmpty else { return }

        if let handler = copyHandler {
            try await handler(context.text)
        }

        context.setCustomData(true, forKey: "clipboard_copy_performed")
    }

    public func cleanup() async {}
}

/// Notification action
public final class NotificationAction: PipelineAction, @unchecked Sendable {
    public let actionTypeId = "notification"
    public var id: String { actionTypeId }
    public let displayName = "Notification"
    public let description = "Show completion notification"
    public let icon = "bell"

    public var constraints: ElementConstraints {
        [.cannotBeFirst, .optional]
    }

    public var connectionRules: ConnectionRules {
        ConnectionRules(
            acceptsInput: [.text, .richText, .any],
            producesOutput: .text
        )
    }

    public var isEnabled: Bool = true

    public var configuration: [String: Any] = [
        "showPreview": true,
        "sound": true,
    ]

    public var notificationHandler: ((String, String) async throws -> Void)?

    public init() {}

    public func prepare() async throws {}

    public func process(_ context: PipelineContext) async throws {
        let showPreview = configuration["showPreview"] as? Bool ?? true

        let title = "Transcription Complete"
        let body = showPreview ? String(context.text.prefix(100)) : "Text ready"

        if let handler = notificationHandler {
            try await handler(title, body)
        }
    }

    public func cleanup() async {}
}
