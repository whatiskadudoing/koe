import SwiftUI

@main
struct WhisperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 380, height: 520)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

enum MenuBarState {
    case loading    // Blue - model loading
    case idle       // White - ready
    case recording  // Red - recording
    case processing // Orange - transcribing
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    private var transcriber: TranscriberService?
    private var menuBarAnimationTimer: Timer?
    private var animationStartTime: Date = Date()
    private var currentAudioLevel: Float = 0.0
    private var menuBarState: MenuBarState = .loading
    private var downloadProgress: Float = 0.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupGlobalHotkey()
        loadTranscriber()
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregister()
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

        // Start with loading animation (blue waveform)
        menuBarState = .loading
        downloadProgress = 0.0
        animationStartTime = Date()
        startMenuBarAnimation()
    }

    @objc func handleDownloadProgress(_ notification: Notification) {
        if let progress = notification.object as? Float {
            DispatchQueue.main.async {
                self.downloadProgress = progress
            }
        }
    }

    @objc func selectLanguage(_ sender: NSMenuItem) {
        guard let langCode = sender.representedObject as? String else { return }

        // Update checkmarks in language menu
        if let languageMenu = sender.menu {
            for item in languageMenu.items {
                item.state = (item.representedObject as? String == langCode) ? .on : .off
            }
        }

        Task { @MainActor in
            AppState.shared.selectedLanguage = langCode
        }
    }

    @objc func selectModel(_ sender: NSMenuItem) {
        guard let modelId = sender.representedObject as? String else { return }

        // Update checkmarks in model menu
        if let modelMenu = sender.menu {
            for item in modelMenu.items {
                item.state = (item.representedObject as? String == modelId) ? .on : .off
            }
        }

        Task { @MainActor in
            // Don't switch if already on this model
            guard modelId != AppState.shared.selectedModel else { return }

            AppState.shared.selectedModel = modelId
            NotificationCenter.default.post(name: .reloadModel, object: modelId)
        }
    }

    @objc func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc func handleModelLoaded() {
        DispatchQueue.main.async {
            self.menuBarState = .idle
            self.downloadProgress = 1.0

            // Show notification that model is ready
            self.showModelReadyNotification()
        }
    }

    private func showModelReadyNotification() {
        // Play pleasant sound to indicate model is ready
        NSSound(named: "Glass")?.play()

        // Show native macOS notification via osascript
        Task { @MainActor in
            let script = """
            display notification "Ready! Hold Option+Space to transcribe." with title "Koe 声" sound name "Glass"
            """

            let process = Process()
            process.launchPath = "/usr/bin/osascript"
            process.arguments = ["-e", script]
            try? process.run()
        }
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

        Task { @MainActor in
            // Immediately mark as not loaded to prevent recording during switch
            AppState.shared.isModelLoaded = false

            // Unload the old model first to free memory and prevent conflicts
            self.transcriber?.unloadModel()

            // Reuse existing transcriber to properly cancel previous loads
            if self.transcriber == nil {
                let transcriber = TranscriberService()
                self.transcriber = transcriber
                RecordingService.shared.setTranscriber(transcriber)
            }

            await self.transcriber?.loadModel(name: modelName)
            AppState.shared.isModelLoaded = true
            NotificationCenter.default.post(name: .modelLoaded, object: nil)
        }
    }

    func setupGlobalHotkey() {
        HotkeyManager.shared.register(
            onKeyDown: {
                Task { @MainActor in
                    RecordingService.shared.startRecording()
                }
            },
            onKeyUp: {
                Task { @MainActor in
                    RecordingService.shared.stopRecording()
                }
            }
        )
    }

    func loadTranscriber() {
        Task { @MainActor in
            let transcriber = TranscriberService()
            self.transcriber = transcriber
            RecordingService.shared.setTranscriber(transcriber)
            await transcriber.loadModel(name: AppState.shared.selectedModel)
            AppState.shared.isModelLoaded = true
            NotificationCenter.default.post(name: .modelLoaded, object: nil)
        }
    }

    @objc func updateMenuBarIcon() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let state = AppState.shared.recordingState

            switch state {
            case .idle:
                // If model is loaded, show white waveform; otherwise keep loading (blue)
                if AppState.shared.isModelLoaded {
                    self.menuBarState = .idle
                }
                // Animation keeps running

            case .recording:
                self.menuBarState = .recording

            case .processing:
                self.menuBarState = .processing
            }
        }
    }

    private func startMenuBarAnimation() {
        guard menuBarAnimationTimer == nil else { return }

        animationStartTime = Date()
        // Higher frequency for smoother animation
        menuBarAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateAnimatedIcon()
        }
    }

    private func stopMenuBarAnimation() {
        menuBarAnimationTimer?.invalidate()
        menuBarAnimationTimer = nil
    }

    private func getLanguageFlag() -> String {
        // Get language on main thread safely
        let lang = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "auto"
        switch lang {
        case "en": return "🇺🇸"
        case "es": return "🇪🇸"
        case "pt": return "🇧🇷"
        default: return "🌐"  // Auto-detect
        }
    }

    private func updateAnimatedIcon() {
        guard let button = statusItem?.button else { return }

        // Use continuous time for smooth animation
        let time = Date().timeIntervalSince(animationStartTime)

        // Determine color and speed based on state
        let color: NSColor
        let audioLevel: Float
        let speed: Double
        var percentText: String? = nil

        switch menuBarState {
        case .loading:
            color = .systemBlue
            audioLevel = 0.6
            speed = 3.0  // Faster animation while loading
            // Show percentage during download, or animated dots for cached loading
            if downloadProgress > 0 && downloadProgress < 1 {
                let percent = Int(downloadProgress * 100)
                percentText = "\(percent)%"
            } else {
                // Animated loading dots
                let dots = Int(time * 2) % 4
                percentText = String(repeating: ".", count: dots + 1)
            }
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

        let flag = getLanguageFlag()
        button.image = createWaveformImage(color: color, audioLevel: audioLevel, time: time, speed: speed, percentText: percentText, flag: flag)
    }

    private func createWaveformImage(color: NSColor, audioLevel: Float, time: Double, speed: Double, percentText: String? = nil, flag: String = "🌐") -> NSImage {
        // Base width for waveform + flag
        let flagWidth: CGFloat = 14
        let waveformWidth: CGFloat = 22
        var width: CGFloat = flagWidth + waveformWidth

        // Extra width if showing percentage
        if percentText != nil {
            width += 28
        }

        let size = NSSize(width: width, height: 18)

        let image = NSImage(size: size, flipped: false) { rect in
            // Draw flag on the left
            let flagAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11)
            ]
            let flagSize = flag.size(withAttributes: flagAttributes)
            let flagY = (rect.height - flagSize.height) / 2
            flag.draw(at: NSPoint(x: 0, y: flagY), withAttributes: flagAttributes)

            // Waveform starts after flag
            let barCount = 5
            let barWidth: CGFloat = 2.5
            let spacing: CGFloat = 1.5
            let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
            let waveformStartX: CGFloat = flagWidth + 2

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
                let x = waveformStartX + CGFloat(i) * (barWidth + spacing)
                let y = (rect.height - barHeight) / 2

                let barRect = NSRect(x: x, y: y, width: barWidth, height: barHeight)
                let path = NSBezierPath(roundedRect: barRect, xRadius: 1, yRadius: 1)
                path.fill()
            }

            // Draw percentage text if provided
            if let text = percentText {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
                    .foregroundColor: color
                ]
                let textSize = text.size(withAttributes: attributes)
                let textX = waveformStartX + totalWidth + 4
                let textY = (rect.height - textSize.height) / 2
                text.draw(at: NSPoint(x: textX, y: textY), withAttributes: attributes)
            }

            return true
        }
        image.isTemplate = false
        return image
    }

    @objc func togglePopover() {
        if let window = NSApplication.shared.windows.first(where: { $0.title == "Whisper" || $0.contentView is NSHostingView<ContentView> }) {
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
