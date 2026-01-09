import Foundation
import AppKit

/// Status of the Ollama setup process
public enum OllamaStatus: Equatable {
    case idle
    case checkingInstallation
    case startingServer
    case pullingModel(progress: String)
    case ready
    case error(String)

    public var displayText: String {
        switch self {
        case .idle: return "AI off"
        case .checkingInstallation: return "checking..."
        case .startingServer: return "starting..."
        case .pullingModel(let progress): return progress.isEmpty ? "downloading model..." : progress
        case .ready: return "ready"
        case .error(let msg): return msg
        }
    }
}

/// Manages the Ollama server lifecycle - auto-start/stop based on refinement toggle
@MainActor
public final class OllamaManager: ObservableObject {
    public static let shared = OllamaManager()

    @Published public private(set) var isRunning = false
    @Published public private(set) var isInstalled = false
    @Published public private(set) var isModelAvailable = false
    @Published public private(set) var status: OllamaStatus = .idle

    /// Default model to use - small and fast
    public static let defaultModel = "llama3.2:3b"

    private var serverProcess: Process?
    private var checkTimer: Timer?
    private var pullTask: Task<Bool, Never>?

    private init() {
        checkInstallation()
    }

    // MARK: - Installation Check

    /// Check if Ollama is installed on the system
    public func checkInstallation() {
        // Check for Ollama.app (macOS app version)
        let appPaths = [
            "/Applications/Ollama.app",
            NSHomeDirectory() + "/Applications/Ollama.app"
        ]

        for appPath in appPaths {
            if FileManager.default.fileExists(atPath: appPath) {
                isInstalled = true
                print("[OllamaManager] Found Ollama.app at: \(appPath)")
                return
            }
        }

        // Check common CLI installation paths
        let paths = [
            "/usr/local/bin/ollama",
            "/opt/homebrew/bin/ollama",
            "/usr/bin/ollama",
            NSHomeDirectory() + "/.ollama/ollama"
        ]

        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                isInstalled = true
                print("[OllamaManager] Found CLI at: \(path)")
                return
            }
        }

        // Try which command
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["ollama"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    isInstalled = true
                    print("[OllamaManager] Found via which: \(path)")
                    return
                }
            }
        } catch {
            // Ignore - will fall through to not installed
        }

        isInstalled = false
        print("[OllamaManager] Not found on system")
    }

    // MARK: - Server Management

    /// Start Ollama server and ensure model is available (auto-pull if needed)
    /// Returns true when fully ready (server running + model available)
    public func startServer(modelName: String? = nil) async -> Bool {
        let model = modelName ?? Self.defaultModel
        status = .checkingInstallation

        // Re-check installation (user might have installed since app launch)
        checkInstallation()

        guard isInstalled else {
            print("[OllamaManager] Cannot start - not installed")
            status = .error("not installed")
            return false
        }

        status = .startingServer

        // First check if already running (e.g., Ollama.app is open)
        if await checkServerRunning() {
            isRunning = true
            print("[OllamaManager] Server already running")
        } else {
            // Try to start Ollama.app first if it exists
            if launchOllamaApp() {
                print("[OllamaManager] Launched Ollama.app")
                // Wait for it to start
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            } else {
                // Fall back to CLI
                let ollamaPath = findOllamaBinary()
                guard let path = ollamaPath else {
                    print("[OllamaManager] Could not find binary")
                    status = .error("binary not found")
                    return false
                }

                // Start the server process
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = ["serve"]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    serverProcess = process
                    print("[OllamaManager] Started server process")
                } catch {
                    print("[OllamaManager] Failed to start server: \(error)")
                    status = .error("failed to start")
                    return false
                }

                // Wait a moment for server to start
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
            }

            // Verify it's running
            if await checkServerRunning() {
                isRunning = true
                print("[OllamaManager] Server started successfully")
            } else {
                print("[OllamaManager] Server not responding")
                status = .error("server not responding")
                return false
            }
        }

        // Check if model is available, auto-pull if not
        await checkModelAvailable(model)

        if !isModelAvailable {
            // Auto-pull the model
            status = .pullingModel(progress: "downloading \(model)...")
            print("[OllamaManager] Model not found, pulling: \(model)")

            let pullSuccess = await pullModel(model)
            if !pullSuccess {
                status = .error("failed to download model")
                return false
            }
        }

        // All good!
        status = .ready
        startHealthCheck()
        return true
    }

    /// Launch Ollama.app if it exists
    private func launchOllamaApp() -> Bool {
        let appPaths = [
            "/Applications/Ollama.app",
            NSHomeDirectory() + "/Applications/Ollama.app"
        ]

        for appPath in appPaths {
            if FileManager.default.fileExists(atPath: appPath) {
                let url = URL(fileURLWithPath: appPath)
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false // Don't bring to front
                NSWorkspace.shared.openApplication(at: url, configuration: config)
                return true
            }
        }
        return false
    }

    /// Stop Ollama server if we started it
    public func stopServer() {
        stopHealthCheck()
        pullTask?.cancel()
        pullTask = nil

        if let process = serverProcess, process.isRunning {
            print("[OllamaManager] Stopping server...")
            process.terminate()
            serverProcess = nil
        }

        isRunning = false
        isModelAvailable = false
        status = .idle
    }

    /// Check if server is responding
    public func checkServerRunning() async -> Bool {
        guard let url = URL(string: "http://localhost:11434/api/tags") else { return false }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                let running = httpResponse.statusCode == 200
                isRunning = running
                return running
            }
        } catch {
            // Server not running
        }

        isRunning = false
        return false
    }

    /// Check if the specified model is available
    private func checkModelAvailable(_ modelName: String) async {
        guard let url = URL(string: "http://localhost:11434/api/tags") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                let modelBase = modelName.split(separator: ":").first.map(String.init) ?? modelName
                let available = models.contains { model in
                    if let name = model["name"] as? String {
                        return name == modelName || name.hasPrefix(modelBase)
                    }
                    return false
                }
                isModelAvailable = available

                if !available {
                    print("[OllamaManager] Model '\(modelName)' not found. Available: \(models.compactMap { $0["name"] as? String })")
                } else {
                    print("[OllamaManager] Model '\(modelName)' is available")
                }
            }
        } catch {
            print("[OllamaManager] Failed to check model availability: \(error)")
        }
    }

    // MARK: - Model Management

    /// Pull a model with progress updates
    public func pullModel(_ modelName: String) async -> Bool {
        guard isRunning else { return false }

        print("[OllamaManager] Pulling model: \(modelName)")
        status = .pullingModel(progress: "downloading...")

        guard let url = URL(string: "http://localhost:11434/api/pull") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["name": modelName, "stream": true])

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("[OllamaManager] Pull request failed")
                return false
            }

            // Stream the response to get progress
            for try await line in bytes.lines {
                if let data = line.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                    // Check for completion
                    if let status = json["status"] as? String, status == "success" {
                        print("[OllamaManager] Model '\(modelName)' pulled successfully")
                        isModelAvailable = true
                        return true
                    }

                    // Update progress
                    if let completed = json["completed"] as? Int64,
                       let total = json["total"] as? Int64,
                       total > 0 {
                        let percent = Int((Double(completed) / Double(total)) * 100)
                        let progressText = "downloading... \(percent)%"
                        self.status = .pullingModel(progress: progressText)
                    } else if let statusText = json["status"] as? String {
                        self.status = .pullingModel(progress: statusText)
                    }
                }
            }

            // Check if model is now available
            await checkModelAvailable(modelName)
            return isModelAvailable
        } catch {
            print("[OllamaManager] Failed to pull model: \(error)")
            return false
        }
    }

    // MARK: - Installation

    /// Show dialog to install Ollama
    public func showInstallDialog() {
        let alert = NSAlert()
        alert.messageText = "Ollama Required"
        alert.informativeText = "AI refinement requires Ollama to be installed. Would you like to install it now?\n\nOllama is a free, local AI runtime that keeps your data private."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install Ollama")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            // Open Ollama download page
            if let url = URL(string: "https://ollama.com/download") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Private Helpers

    private func findOllamaBinary() -> String? {
        let paths = [
            "/usr/local/bin/ollama",
            "/opt/homebrew/bin/ollama",
            "/usr/bin/ollama"
        ]

        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        return nil
    }

    private func startHealthCheck() {
        checkTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                _ = await self?.checkServerRunning()
            }
        }
    }

    private func stopHealthCheck() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    // MARK: - Cleanup

    deinit {
        // Note: This won't be called on MainActor, so we schedule cleanup
        Task { @MainActor in
            OllamaManager.shared.stopServer()
        }
    }
}
