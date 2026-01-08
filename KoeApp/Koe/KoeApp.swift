import SwiftUI
import KoeDomain
import KoeAudio
import KoeTranscription
import KoeHotkey
import KoeTextInsertion
import KoeStorage
import KoeUI
import KoeCore
import KoeMeeting

@main
struct KoeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState.shared
    // Use the shared coordinator instance
    @State private var coordinator = RecordingCoordinator.shared
    @State private var meetingCoordinator = MeetingCoordinator.shared
    // Mode manager for coordinating dictation and meeting modes
    @State private var modeManager = ModeManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(coordinator)
                .environment(meetingCoordinator)
                .environment(modeManager)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 380, height: 520)

        Settings {
            SettingsView()
                .environment(appState)
                .environment(coordinator)
                .environment(meetingCoordinator)
                .environment(modeManager)
        }
    }
}

enum MenuBarState {
    case loading    // Blue - model loading
    case idle       // White - ready
    case recording  // Red - recording
    case processing // Orange - transcribing
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    private var menuBarAnimationTimer: Timer?
    private var animationStartTime: Date = Date()
    private var currentAudioLevel: Float = 0.0
    private var menuBarState: MenuBarState = .loading
    private var downloadProgress: Float = 0.0

    // Use the shared coordinator
    private var coordinator: RecordingCoordinator {
        RecordingCoordinator.shared
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        // NOTE: Model loading is now triggered by LoadingView when permissions are granted
        // This prevents file access dialogs from appearing before the user goes through permissions

        // Start meeting detection early - it doesn't need the model
        Task {
            await MeetingCoordinator.shared.startMonitoring()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.unregisterHotkey()
        menuBarAnimationTimer?.invalidate()
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Create menu
        let menu = NSMenu()
        menu.delegate = self

        // Language selection submenu
        let languageMenu = NSMenu()
        let languages = [
            ("en", "🇺🇸 English"),
            ("es", "🇪🇸 Español"),
            ("pt", "🇧🇷 Português"),
            ("auto", "🌐 Auto-detect")
        ]

        let currentLanguage = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "auto"
        for (code, name) in languages {
            let item = NSMenuItem(title: name, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            item.state = (code == currentLanguage) ? .on : .off
            languageMenu.addItem(item)
        }

        let languageMenuItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        languageMenuItem.submenu = languageMenu
        menu.addItem(languageMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Model selection submenu
        let modelMenu = NSMenu()
        let models = [
            ("tiny", "Tiny - Fastest"),
            ("base", "Base - Fast"),
            ("small", "Small - Balanced"),
            ("medium", "Medium - Accurate"),
            ("large-v3", "Large - Best")
        ]

        let currentModel = UserDefaults.standard.string(forKey: "selectedModel") ?? "tiny"
        for (id, name) in models {
            let item = NSMenuItem(title: name, action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
            item.state = (id == currentModel) ? .on : .off
            modelMenu.addItem(item)
        }

        let modelMenuItem = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        modelMenuItem.submenu = modelMenu
        menu.addItem(modelMenuItem)

        // Info about multilingual support
        let infoItem = NSMenuItem(title: "✨ All models support all languages", action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        menu.addItem(infoItem)

        menu.addItem(NSMenuItem.separator())

        // Open window
        let openItem = NSMenuItem(title: "Open Koe", action: #selector(togglePopover), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        // Settings
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit Koe", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu

        // Observe state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateMenuBarIcon),
            name: .appStateChanged,
            object: nil
        )

        // Observe model reload requests
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleModelReload),
            name: .reloadModel,
            object: nil
        )

        // Observe audio level changes for menu bar waveform
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioLevelUpdate),
            name: .audioLevelChanged,
            object: nil
        )

        // Observe model loaded state
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleModelLoaded),
            name: .modelLoaded,
            object: nil
        )

        // Observe download progress
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDownloadProgress),
            name: .modelDownloadProgress,
            object: nil
        )

        // Observe app ready state
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppReady),
            name: .appReady,
            object: nil
        )

        // Start with loading animation (blue waveform)
        menuBarState = .loading
        downloadProgress = 0.0
        animationStartTime = Date()
        startMenuBarAnimation()
    }

    @objc func handleDownloadProgress(_ notification: Notification) {
        if let progress = notification.object as? Float {
            downloadProgress = progress
        }
    }

    @objc func handleAppReady() {
        setupGlobalHotkey()
        coordinator.initializeWhenReady()
        // Note: Meeting monitoring is started in applicationDidFinishLaunching
    }

    @objc func selectLanguage(_ sender: NSMenuItem) {
        guard let langCode = sender.representedObject as? String else { return }

        // Update checkmarks in language menu
        if let languageMenu = sender.menu {
            for item in languageMenu.items {
                item.state = (item.representedObject as? String == langCode) ? .on : .off
            }
        }

        AppState.shared.selectedLanguage = langCode
    }

    @objc func selectModel(_ sender: NSMenuItem) {
        guard let modelId = sender.representedObject as? String else { return }

        // Update checkmarks in model menu
        if let modelMenu = sender.menu {
            for item in modelMenu.items {
                item.state = (item.representedObject as? String == modelId) ? .on : .off
            }
        }

        // Don't switch if already on this model
        guard modelId != AppState.shared.selectedModel else { return }

        AppState.shared.selectedModel = modelId
        NotificationCenter.default.post(name: .reloadModel, object: modelId)
    }

    @objc func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc func handleModelLoaded() {
        menuBarState = .idle
        downloadProgress = 1.0

        // Show notification that model is ready
        showModelReadyNotification()
    }

    private func showModelReadyNotification() {
        // Play pleasant sound to indicate model is ready
        NSSound(named: "Glass")?.play()

        // Show native macOS notification via osascript
        let script = """
        display notification "Ready! Hold Option+Space to transcribe." with title "Koe 声" sound name "Glass"
        """

        let process = Process()
        process.launchPath = "/usr/bin/osascript"
        process.arguments = ["-e", script]
        try? process.run()
    }

    @objc func handleAudioLevelUpdate(_ notification: Notification) {
        if let level = notification.object as? Float {
            currentAudioLevel = level
        }
    }

    @objc func handleModelReload(_ notification: Notification) {
        guard let modelName = notification.object as? String else { return }

        // Set loading state (blue waveform)
        menuBarState = .loading
        downloadProgress = 0.01

        Task {
            // Unload and reload using coordinator
            coordinator.unloadModel()
            await coordinator.loadModel(name: modelName)
        }
    }

    func setupGlobalHotkey() {
        coordinator.setupHotkey()
    }

    func loadModel() {
        Task {
            await coordinator.loadModel(name: AppState.shared.selectedModel)
        }
    }

    @objc func updateMenuBarIcon() {
        let state = AppState.shared.recordingState

        switch state {
        case .idle:
            // If model is loaded, show white waveform; otherwise keep loading (blue)
            if AppState.shared.isModelLoaded {
                menuBarState = .idle
            }

        case .recording:
            menuBarState = .recording

        case .processing:
            menuBarState = .processing
        }

        // Optimize timer: fast animation when active, slow when idle
        adjustTimerForState()
    }

    private func adjustTimerForState() {
        let needsFastAnimation = (menuBarState == .loading || menuBarState == .recording || menuBarState == .processing)

        if needsFastAnimation {
            // Fast animation (20fps) for active states
            startMenuBarAnimation(interval: 0.05)
        } else {
            // Slow animation (2fps) when idle - just subtle breathing
            startMenuBarAnimation(interval: 0.5)
        }
    }

    private func startMenuBarAnimation(interval: TimeInterval = 0.05) {
        // If timer exists with same interval, keep it
        if menuBarAnimationTimer != nil {
            // Check if we need to change interval by stopping and restarting
            menuBarAnimationTimer?.invalidate()
        }

        animationStartTime = Date()
        menuBarAnimationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateAnimatedIcon()
            }
        }
    }

    private func stopMenuBarAnimation() {
        menuBarAnimationTimer?.invalidate()
        menuBarAnimationTimer = nil
    }

    private func updateAnimatedIcon() {
        guard let button = statusItem?.button else { return }

        // Use continuous time for smooth animation
        let time = Date().timeIntervalSince(animationStartTime)

        // Determine color and speed based on state
        let color: NSColor
        let audioLevel: Float
        let speed: Double

        switch menuBarState {
        case .loading:
            color = .systemBlue
            audioLevel = 0.6
            speed = 3.0  // Faster animation while loading
        case .idle:
            color = .white
            audioLevel = 0.3
            speed = 1.5  // Slow, subtle
        case .recording:
            color = .systemRed
            audioLevel = max(0.4, currentAudioLevel)  // Minimum visibility
            speed = 4.0  // Fast, responsive
        case .processing:
            color = .systemOrange
            audioLevel = 0.6
            speed = 3.0  // Active
        }

        button.image = createWaveformImage(color: color, audioLevel: audioLevel, time: time, speed: speed)
    }

    private func createWaveformImage(color: NSColor, audioLevel: Float, time: Double, speed: Double) -> NSImage {
        // Just the waveform, no text
        let barCount = 5
        let barWidth: CGFloat = 2.5
        let spacing: CGFloat = 1.5
        let width: CGFloat = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing + 4  // Add small padding
        let size = NSSize(width: width, height: 18)

        let image = NSImage(size: size, flipped: false) { rect in
            color.setFill()

            for i in 0..<barCount {
                // Smooth continuous wave using time
                let phaseOffset = Double(i) * 0.9
                let wave1 = sin(time * speed + phaseOffset)
                let wave2 = sin(time * speed * 0.7 + phaseOffset * 1.3) * 0.5

                let combinedWave = (wave1 + wave2) / 1.5
                let normalizedWave = (combinedWave + 1) / 2

                let levelFactor = CGFloat(0.3 + audioLevel * 0.7)
                let heightRatio = CGFloat(0.15 + normalizedWave * 0.85) * levelFactor

                let barHeight = max(3, rect.height * heightRatio)
                let x = 2 + CGFloat(i) * (barWidth + spacing)  // Start with small padding
                let y = (rect.height - barHeight) / 2

                let barRect = NSRect(x: x, y: y, width: barWidth, height: barHeight)
                let path = NSBezierPath(roundedRect: barRect, xRadius: 1, yRadius: 1)
                path.fill()
            }

            return true
        }
        image.isTemplate = false
        return image
    }

    @objc func togglePopover() {
        if let window = NSApplication.shared.windows.first(where: { $0.title == "Koe" || $0.contentView is NSHostingView<ContentView> }) {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        } else {
            NSApplication.shared.activate(ignoringOtherApps: true)
            if let window = NSApplication.shared.windows.first {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}

extension Notification.Name {
    static let appStateChanged = Notification.Name("appStateChanged")
    static let audioLevelChanged = Notification.Name("audioLevelChanged")
    static let modelLoaded = Notification.Name("modelLoaded")
    static let modelDownloadProgress = Notification.Name("modelDownloadProgress")
    static let appReady = Notification.Name("appReady")

    // Mode coordination notifications
    static let dictationStarted = Notification.Name("dictationStarted")
    static let dictationEnded = Notification.Name("dictationEnded")
    static let requestPauseMeetingDetection = Notification.Name("requestPauseMeetingDetection")
    static let requestResumeMeetingDetection = Notification.Name("requestResumeMeetingDetection")
    static let meetingDetectedSwitchTab = Notification.Name("meetingDetectedSwitchTab")
    static let meetingEndedSwitchTab = Notification.Name("meetingEndedSwitchTab")
}

// MARK: - NSMenuDelegate
extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // Update checkmarks when menu opens to ensure they reflect current state
        let currentLanguage = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "auto"
        let currentModel = UserDefaults.standard.string(forKey: "selectedModel") ?? "tiny"

        for item in menu.items {
            if let submenu = item.submenu {
                // Language submenu
                if item.title == "Language" {
                    for langItem in submenu.items {
                        langItem.state = (langItem.representedObject as? String == currentLanguage) ? .on : .off
                    }
                }
                // Model submenu
                if item.title == "Model" {
                    for modelItem in submenu.items {
                        modelItem.state = (modelItem.representedObject as? String == currentModel) ? .on : .off
                    }
                }
            }
        }
    }
}
