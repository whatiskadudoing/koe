import HotKey
import AppKit

class HotkeyManager {
    static let shared = HotkeyManager()

    private var hotKey: HotKey?
    private var onKeyDown: (() -> Void)?
    private var onKeyUp: (() -> Void)?

    private init() {}

    func register(onKeyDown: @escaping () -> Void, onKeyUp: @escaping () -> Void) {
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp

        // Option + Space
        hotKey = HotKey(key: .space, modifiers: [.option])

        hotKey?.keyDownHandler = { [weak self] in
            print("🎤 Hotkey pressed - start recording")
            self?.onKeyDown?()
        }

        hotKey?.keyUpHandler = { [weak self] in
            print("🛑 Hotkey released - stop recording")
            self?.onKeyUp?()
        }

        print("✅ Global hotkey registered: Option+Space (hold to record)")
    }

    func unregister() {
        hotKey = nil
    }
}
