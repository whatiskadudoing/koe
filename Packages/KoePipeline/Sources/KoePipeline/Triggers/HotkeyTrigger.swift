import Foundation

/// Represents a keyboard shortcut
public struct KeyboardShortcut: Codable, Sendable, Equatable, Hashable {
    /// Key code (virtual key code)
    public var keyCode: UInt32

    /// Modifier flags
    public var modifiers: KeyModifiers

    /// Human-readable display string
    public var displayString: String {
        var parts: [String] = []

        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }

        parts.append(keyName)

        return parts.joined()
    }

    /// Key name for display
    private var keyName: String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 51: return "Delete"
        case 53: return "Escape"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            // Convert key code to character
            if let char = KeyboardShortcut.keyCodeToChar[keyCode] {
                return char.uppercased()
            }
            return "Key\(keyCode)"
        }
    }

    /// Common key code to character mapping
    private static let keyCodeToChar: [UInt32: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
        8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
        16: "y", 17: "t", 31: "o", 32: "u", 34: "i", 35: "p", 37: "l",
        38: "j", 40: "k", 45: "n", 46: "m",
    ]

    // MARK: - Presets

    /// Default: Option + Space
    public static let optionSpace = KeyboardShortcut(
        keyCode: 49,  // Space
        modifiers: .option
    )

    /// Alternative: Command + Shift + Space
    public static let commandShiftSpace = KeyboardShortcut(
        keyCode: 49,
        modifiers: [.command, .shift]
    )

    /// Alternative: Control + Space
    public static let controlSpace = KeyboardShortcut(
        keyCode: 49,
        modifiers: .control
    )

    /// Alternative: F5
    public static let f5 = KeyboardShortcut(
        keyCode: 96,  // F5
        modifiers: []
    )

    public init(keyCode: UInt32, modifiers: KeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

/// Keyboard modifier flags
public struct KeyModifiers: OptionSet, Codable, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let option = KeyModifiers(rawValue: 1 << 1)
    public static let control = KeyModifiers(rawValue: 1 << 2)
    public static let shift = KeyModifiers(rawValue: 1 << 3)

    public static let none: KeyModifiers = []
}

/// Configuration for hotkey trigger
public struct HotkeyTriggerConfig: Codable, Sendable, Equatable {
    /// The keyboard shortcut
    public var shortcut: KeyboardShortcut

    /// Whether to trigger on key down (press) or key up (release)
    public var triggerOnKeyDown: Bool

    /// Whether to trigger on key up (for hold-to-record)
    public var triggerOnKeyUp: Bool

    /// Default: Option + Space, hold-to-record style
    public static let `default` = HotkeyTriggerConfig(
        shortcut: .optionSpace,
        triggerOnKeyDown: true,
        triggerOnKeyUp: true
    )

    /// Push-to-talk: only trigger while held
    public static let pushToTalk = HotkeyTriggerConfig(
        shortcut: .optionSpace,
        triggerOnKeyDown: true,
        triggerOnKeyUp: true
    )

    /// Toggle: press once to start, press again to stop
    public static let toggle = HotkeyTriggerConfig(
        shortcut: .optionSpace,
        triggerOnKeyDown: true,
        triggerOnKeyUp: false
    )

    public init(shortcut: KeyboardShortcut, triggerOnKeyDown: Bool, triggerOnKeyUp: Bool) {
        self.shortcut = shortcut
        self.triggerOnKeyDown = triggerOnKeyDown
        self.triggerOnKeyUp = triggerOnKeyUp
    }
}

/// Trigger that starts/stops pipeline via keyboard shortcut
/// This is a special element that handles input rather than processing data
public final class HotkeyTrigger: PipelineAction, @unchecked Sendable {
    public let actionTypeId = "hotkey-trigger"
    public var id: String { actionTypeId }
    public let displayName = "Hotkey"
    public let description = "Keyboard shortcut to trigger pipeline"
    public let icon = "keyboard.badge.ellipsis"

    public var constraints: ElementConstraints {
        [.mustBeFirst, .optional]
    }

    public var connectionRules: ConnectionRules {
        ConnectionRules(
            acceptsInput: [],
            producesOutput: .any
        )
    }

    public var isEnabled: Bool = true

    public var configuration: [String: Any] {
        get {
            [
                "keyCode": config.shortcut.keyCode,
                "modifiers": config.shortcut.modifiers.rawValue,
                "triggerOnKeyDown": config.triggerOnKeyDown,
                "triggerOnKeyUp": config.triggerOnKeyUp,
            ]
        }
        set {
            if let keyCode = newValue["keyCode"] as? UInt32,
                let modifiersRaw = newValue["modifiers"] as? Int
            {
                config.shortcut = KeyboardShortcut(
                    keyCode: keyCode,
                    modifiers: KeyModifiers(rawValue: modifiersRaw)
                )
            }
            if let v = newValue["triggerOnKeyDown"] as? Bool { config.triggerOnKeyDown = v }
            if let v = newValue["triggerOnKeyUp"] as? Bool { config.triggerOnKeyUp = v }
        }
    }

    // MARK: - Trigger-Specific

    public var config: HotkeyTriggerConfig = .default

    /// Handler called when hotkey is pressed (key down)
    public var onKeyDown: (() async -> Void)?

    /// Handler called when hotkey is released (key up)
    public var onKeyUp: (() async -> Void)?

    /// Handler to register the hotkey with the system
    public var registerHandler: ((KeyboardShortcut, @escaping () -> Void, @escaping () -> Void) -> Void)?

    /// Handler to unregister the hotkey
    public var unregisterHandler: (() -> Void)?

    // MARK: - State

    private var isRegistered = false

    // MARK: - Initialization

    public init(config: HotkeyTriggerConfig = .default) {
        self.config = config
    }

    // MARK: - Processing

    public func prepare() async throws {
        // Register hotkey if handler provided
        guard let register = registerHandler else { return }

        register(
            config.shortcut,
            { [weak self] in
                guard let self = self, self.config.triggerOnKeyDown else { return }
                Task {
                    await self.onKeyDown?()
                }
            },
            { [weak self] in
                guard let self = self, self.config.triggerOnKeyUp else { return }
                Task {
                    await self.onKeyUp?()
                }
            })

        isRegistered = true
    }

    public func process(_ context: PipelineContext) async throws {
        // Hotkey trigger doesn't process data - it triggers the pipeline
        // The actual start/stop is handled by onKeyDown/onKeyUp callbacks
    }

    public func cleanup() async {
        if isRegistered {
            unregisterHandler?()
            isRegistered = false
        }
    }
}

// MARK: - Preset Shortcuts

extension KeyboardShortcut {
    /// All available preset shortcuts
    public static let presets: [KeyboardShortcut] = [
        .optionSpace,
        .commandShiftSpace,
        .controlSpace,
        .f5,
    ]

    /// Preset names for UI
    public static let presetNames: [KeyboardShortcut: String] = [
        .optionSpace: "Option + Space (Default)",
        .commandShiftSpace: "Command + Shift + Space",
        .controlSpace: "Control + Space",
        .f5: "F5",
    ]
}
