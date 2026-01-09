import SwiftUI
import UserNotifications
import KoeDomain
import KoeAudio
import KoeTranscription
import KoeHotkey
import KoeTextInsertion
import KoeStorage
import KoeUI
import KoeCore
import KoeMeeting
import KoeCommands
import os.log

private let logger = Logger(subsystem: "com.koe.voice", category: "AppDelegate")

@main
struct KoeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState.shared
    // Use the shared coordinator instance
    @State private var coordinator = RecordingCoordinator.shared
    @State private var meetingCoordinator = MeetingCoordinator.shared
    // Mode manager for coordinating dictation and meeting modes
    @State private var modeManager = ModeManager.shared

    /// Check if running in precompile mode (headless model compilation)
    static var isPrecompileMode: Bool {
        CommandLine.arguments.contains("--precompile")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if Self.isPrecompileMode {
                    // Minimal view for precompile mode - no UI needed
                    Color.clear
                        .frame(width: 1, height: 1)
                } else {
                    ContentView()
                        .environment(appState)
                        .environment(coordinator)
                        .environment(meetingCoordinator)
                        .environment(modeManager)
                }
            }
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
    case loading      // Blue - model loading
    case idle         // White - ready
    case recording    // Red - recording
    case transcribing // Yellow - transcribing audio
    case refining     // Purple - AI refinement
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem?
    private var menuBarAnimationTimer: Timer?
    private var animationStartTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private var currentTimerInterval: TimeInterval?
    private var currentAudioLevel: Float = 0.0
    private var menuBarState: MenuBarState = .loading
    private var downloadProgress: Float = 0.0

    // Voice command detector
    private let commandDetector = CommandDetector()

    // Trigger system
    private var triggerManager: TriggerManager?
    private var hotkeyTrigger: HotkeyTrigger?

    // Use the shared coordinator
    private var coordinator: RecordingCoordinator {
        RecordingCoordinator.shared
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check for precompile mode first
        if KoeApp.isPrecompileMode {
            runPrecompileAndExit()
            return
        }

        NSLog("🚀 Koe app launched!")

        // Set notification delegate for handling model ready notifications
        UNUserNotificationCenter.current().delegate = self

        setupMenuBar()
        setupCommandDetector()
        // NOTE: Model loading is now triggered by LoadingView when permissions are granted
        // This prevents file access dialogs from appearing before the user goes through permissions

        // Start meeting detection early - it doesn't need the model
        Task {
            await MeetingCoordinator.shared.startMonitoring()
        }
    }

    /// Run headless model precompilation and exit (called by installer)
    private func runPrecompileAndExit() {
        // Flush stdout immediately for installer to see progress
        setbuf(stdout, nil)

        print("[Koe] Starting model precompilation...")
        fflush(stdout)

        Task {
            let startTime = Date()

            do {
                let transcriber = WhisperKitTranscriber()

                // Compile the default (fast) model
                print("[Koe] Loading Fast model...")
                fflush(stdout)

                // Subscribe to progress updates
                let progressStream = transcriber.loadingProgressStream()

                // Start loading in background
                let loadTask = Task {
                    try await transcriber.loadModel(.fast)
                }

                // Print progress updates
                var lastProgress: Int = -1
                var inCompilationPhase = false
                for await progress in progressStream {
                    let percent = Int(progress * 100)

                    // Detect compilation phase (progress = -1 means animated/compiling)
                    if progress < 0 && !inCompilationPhase {
                        inCompilationPhase = true
                        print("[Koe] Compiling for Apple Neural Engine (this takes 3-4 minutes on first run)...")
                        fflush(stdout)
                    }

                    if percent != lastProgress && percent >= 0 {
                        print("[Koe] Progress: \(percent)%")
                        fflush(stdout)
                        lastProgress = percent
                    }
                    if progress >= 1.0 {
                        break
                    }
                }

                // Wait for load to complete
                try await loadTask.value

                let elapsed = Date().timeIntervalSince(startTime)
                print("[Koe] Fast model compiled successfully in \(String(format: "%.1f", elapsed))s")
                fflush(stdout)

                print("[Koe] Precompilation complete!")
                fflush(stdout)

                // Exit successfully
                exit(0)
            } catch {
                print("[Koe] Precompilation failed: \(error)")
                fflush(stdout)
                exit(1)
            }
        }
    }

    private func setupCommandDetector() {
        // Observe command listening state changes
        NotificationCenter.default.addObserver(
            forName: .commandListeningChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.updateCommandListening()
            }
        }

        // Observe voice profile training completion
        NotificationCenter.default.addObserver(
            forName: .voiceProfileTrained,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.commandDetector.reloadProfile()
            logger.notice("[AppDelegate] Voice profile reloaded after training")
        }

        // Observe voice command settings changes
        NotificationCenter.default.addObserver(
            forName: .voiceCommandSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            // Sync settings from AppState to CommandDetector
            let newSettings = AppState.shared.voiceCommandSettings
            self.commandDetector.settings = newSettings
            logger.notice("[AppDelegate] Voice command settings updated: VAD=\(newSettings.vadEnabled), threshold=\(newSettings.confidenceThreshold)")
        }

        // Set up command handler - actually execute the detected command
        commandDetector.onCommandDetected = { [weak self] result in
            guard let self = self else { return }
            logger.notice("[CommandDetector] Command detected: \(result.command.trigger) (confidence: \(result.confidence), verified: \(result.isVoiceVerified))")

            guard result.shouldExecute else {
                logger.notice("[CommandDetector] Command not executed: shouldExecute=false")
                return
            }

            // Execute the command action
            Task { @MainActor in
                self.executeCommandAction(result.command.action)
            }
        }

        // Observe voice command start recording notification
        NotificationCenter.default.addObserver(
            forName: .startRecordingFromVoiceCommand,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                // Mark this as a voice command triggered recording
                AppState.shared.isVoiceCommandTriggered = true

                // Start recording with VAD mode (voice command uses silence detection)
                let langCode = AppState.shared.selectedLanguage
                let language = Language.all.first { $0.code == langCode } ?? .auto
                await self.coordinator.startRecording(mode: .vad, language: language)
                logger.notice("[AppDelegate] Voice command triggered recording started")
            }
        }

        // Observe voice command stop recording notification
        NotificationCenter.default.addObserver(
            forName: .stopRecordingFromVoiceCommand,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                let langCode = AppState.shared.selectedLanguage
                let language = Language.all.first { $0.code == langCode } ?? .auto
                await self.coordinator.stopRecording(mode: .vad, language: language)
                AppState.shared.isVoiceCommandTriggered = false
                logger.notice("[AppDelegate] Voice command triggered recording stopped")
            }
        }

        // Start listening if enabled and profile exists
        Task {
            await updateCommandListening()
        }
    }

    private func updateCommandListening() async {
        let appState = AppState.shared
        logger.notice("[AppDelegate] updateCommandListening: enabled=\(appState.isCommandListeningEnabled), hasProfile=\(appState.hasVoiceProfile)")

        if appState.isCommandListeningEnabled && appState.hasVoiceProfile {
            logger.notice("[AppDelegate] Starting command detection...")
            await commandDetector.startDetection()
        } else {
            logger.notice("[AppDelegate] Stopping command detection")
            commandDetector.stopDetection()
        }
    }

    @MainActor
    private func executeCommandAction(_ action: CommandAction) {
        logger.notice("[AppDelegate] Executing command action: \(String(describing: action))")

        switch action {
        case .notification(let title, let body):
            // Send a user notification
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
            logger.notice("[AppDelegate] Notification sent: \(title)")

        case .startRecording:
            // Post notification to start recording
            NotificationCenter.default.post(name: .startRecordingFromVoiceCommand, object: nil)
            logger.notice("[AppDelegate] Start recording notification posted")

        case .stopRecording:
            // Post notification to stop recording
            NotificationCenter.default.post(name: .stopRecordingFromVoiceCommand, object: nil)
            logger.notice("[AppDelegate] Stop recording notification posted")

        case .togglePipelineOption(let option):
            // Toggle a pipeline option
            NotificationCenter.default.post(
                name: .togglePipelineOptionFromVoiceCommand,
                object: nil,
                userInfo: ["option": option]
            )
            logger.notice("[AppDelegate] Toggle pipeline option: \(option)")

        case .custom(let identifier):
            // Custom action - post notification with identifier
            NotificationCenter.default.post(
                name: .customVoiceCommandAction,
                object: nil,
                userInfo: ["identifier": identifier]
            )
            logger.notice("[AppDelegate] Custom action: \(identifier)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up trigger system
        Task {
            await triggerManager?.unregisterAll()
        }
        commandDetector.stopDetection()
        menuBarAnimationTimer?.invalidate()
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Create simplified menu - just Open and Quit
        let menu = NSMenu()

        // Open window
        let openItem = NSMenuItem(title: "Open Koe", action: #selector(togglePopover), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

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

        // Observe hotkey changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHotkeyChanged),
            name: .hotkeyChanged,
            object: nil
        )

        // Start with loading animation (blue waveform)
        menuBarState = .loading
        downloadProgress = 0.0
        animationStartTime = CFAbsoluteTimeGetCurrent()
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

        // Start background model downloading/compilation
        // Only start automatically if user has already seen the explanation (returning users)
        // New users will see the explanation first, and processing starts when they dismiss it
        Task { @MainActor in
            let hasSeenExplanation = UserDefaults.standard.bool(forKey: "HasSeenBackgroundExplanation")
            if hasSeenExplanation {
                BackgroundModelService.shared.startBackgroundProcessing()
            }
        }

        // Setup notification categories for model ready actions
        setupNotificationCategories()
    }

    private func setupNotificationCategories() {
        let switchAction = UNNotificationAction(
            identifier: "SWITCH_MODEL",
            title: "Switch Now",
            options: [.foreground]
        )

        let laterAction = UNNotificationAction(
            identifier: "LATER",
            title: "Later",
            options: []
        )

        let category = UNNotificationCategory(
            identifier: "MODEL_READY",
            actions: [switchAction, laterAction],
            intentIdentifiers: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    @objc func handleHotkeyChanged() {
        // Update the hotkey trigger with new settings
        hotkeyTrigger?.updateShortcut(
            keyCode: AppState.shared.hotkeyKeyCode,
            modifiers: AppState.shared.hotkeyModifiers
        )
        logger.notice("Hotkey updated: \(AppState.shared.hotkeyDisplayString)")
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
        // Use the new trigger system
        Task {
            await setupTriggers()
        }
    }

    private func setupTriggers() async {
        let manager = TriggerManager()
        let hotkeyManager = KoeHotkeyManager()
        let trigger = HotkeyTrigger(hotkeyManager: hotkeyManager)

        // Configure shortcut from AppState
        trigger.updateShortcut(
            keyCode: AppState.shared.hotkeyKeyCode,
            modifiers: AppState.shared.hotkeyModifiers
        )

        // Register the trigger
        do {
            try await manager.register(trigger)
        } catch {
            logger.error("Failed to register hotkey trigger: \(error)")
        }

        // Wire up coordinator to trigger events
        coordinator.subscribeTo(triggerManager: manager)

        // Store references
        self.triggerManager = manager
        self.hotkeyTrigger = trigger

        logger.notice("Trigger system initialized with hotkey: \(AppState.shared.hotkeyDisplayString)")
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

        case .transcribing:
            menuBarState = .transcribing

        case .refining:
            menuBarState = .refining
        }

        // Optimize timer: fast animation when active, slow when idle
        adjustTimerForState()
    }

    private func adjustTimerForState() {
        let needsFastAnimation = (menuBarState == .loading || menuBarState == .recording || menuBarState == .transcribing || menuBarState == .refining)

        if needsFastAnimation {
            // Smooth animation (30fps) for active states
            startMenuBarAnimation(interval: 1.0 / 30.0)
        } else {
            // Slow animation (4fps) when idle - subtle breathing
            startMenuBarAnimation(interval: 0.25)
        }
    }

    private func startMenuBarAnimation(interval: TimeInterval = 1.0 / 30.0) {
        // Only recreate timer if interval actually changed
        if currentTimerInterval == interval && menuBarAnimationTimer != nil {
            return
        }

        menuBarAnimationTimer?.invalidate()
        currentTimerInterval = interval
        animationStartTime = CFAbsoluteTimeGetCurrent()

        // Use RunLoop.main directly for lower latency
        menuBarAnimationTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateAnimatedIcon()
            }
        }
        RunLoop.main.add(menuBarAnimationTimer!, forMode: .common)
    }

    private func stopMenuBarAnimation() {
        menuBarAnimationTimer?.invalidate()
        menuBarAnimationTimer = nil
        currentTimerInterval = nil
    }

    private func updateAnimatedIcon() {
        guard let button = statusItem?.button else { return }

        // Use continuous time for smooth animation (CFAbsoluteTime is more efficient than Date)
        let time = CFAbsoluteTimeGetCurrent() - animationStartTime

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
            // Red for recording
            color = KoeColors.nsColor(for: .recording)
            audioLevel = max(0.4, currentAudioLevel)  // Minimum visibility
            speed = 4.0  // Fast, responsive
        case .transcribing:
            // Yellow for transcribing
            color = KoeColors.nsColor(for: .transcribing)
            audioLevel = 0.6
            speed = 3.0  // Active
        case .refining:
            // Purple for AI refinement
            color = KoeColors.nsColor(for: .refining)
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

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        if response.notification.request.content.categoryIdentifier == "MODEL_READY",
           let modelRaw = userInfo["modelRawValue"] as? String,
           let model = KoeModel(rawValue: modelRaw) {

            switch response.actionIdentifier {
            case "SWITCH_MODEL":
                // Switch to the new model
                Task { @MainActor in
                    AppState.shared.selectedModel = model.rawValue
                    await RecordingCoordinator.shared.loadModel(model)
                    logger.notice("Switched to model: \(model.shortName)")
                }
            case "LATER", UNNotificationDefaultActionIdentifier:
                // Just open the app
                Task { @MainActor in
                    self.togglePopover()
                }
            default:
                break
            }
        }

        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
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

    // Hotkey configuration
    static let hotkeyChanged = Notification.Name("hotkeyChanged")

    // Voice commands
    static let commandListeningChanged = Notification.Name("commandListeningChanged")
    static let voiceProfileTrained = Notification.Name("voiceProfileTrained")
    static let voiceCommandSettingsChanged = Notification.Name("voiceCommandSettingsChanged")

    // Voice command actions
    static let startRecordingFromVoiceCommand = Notification.Name("startRecordingFromVoiceCommand")
    static let stopRecordingFromVoiceCommand = Notification.Name("stopRecordingFromVoiceCommand")
    static let togglePipelineOptionFromVoiceCommand = Notification.Name("togglePipelineOptionFromVoiceCommand")
    static let customVoiceCommandAction = Notification.Name("customVoiceCommandAction")

    // UI navigation
    static let showVoiceTraining = Notification.Name("showVoiceTraining")
}

