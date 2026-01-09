import Foundation

/// HTTP client for communicating with Ollama API
public struct OllamaClient: Sendable {
    public let endpoint: URL

    public init(endpoint: URL = URL(string: "http://localhost:11434")!) {
        self.endpoint = endpoint
    }

    public init(endpointString: String) {
        self.endpoint = URL(string: endpointString) ?? URL(string: "http://localhost:11434")!
    }

    // MARK: - Generate Text

    /// Generate text using a model
    public func generate(
        model: String,
        prompt: String,
        system: String? = nil,
        temperature: Double = 0.7,
        timeout: TimeInterval = 30
    ) async throws -> String {
        let url = endpoint.appendingPathComponent("api/generate")

        var body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": [
                "temperature": temperature
            ]
        ]

        if let system = system, !system.isEmpty {
            body["system"] = system
        }

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw OllamaError.modelNotFound(model)
            }
            throw OllamaError.serverError(httpResponse.statusCode)
        }

        let result = try JSONDecoder().decode(GenerateResponse.self, from: data)
        return result.response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - List Models

    /// List available models on the Ollama server
    public func listModels() async throws -> [OllamaModel] {
        let url = endpoint.appendingPathComponent("api/tags")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw OllamaError.serverError(httpResponse.statusCode)
        }

        let result = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return result.models
    }

    // MARK: - Check Connection

    /// Check if Ollama server is running and accessible
    public func checkConnection() async -> Bool {
        do {
            _ = try await listModels()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Check Model Available

    /// Check if a specific model is available
    public func isModelAvailable(_ model: String) async -> Bool {
        do {
            let models = try await listModels()
            return models.contains { $0.name == model || $0.name.hasPrefix("\(model):") }
        } catch {
            return false
        }
    }
}

// MARK: - Response Types

struct GenerateResponse: Codable {
    let model: String
    let response: String
    let done: Bool
    let totalDuration: Int64?
    let loadDuration: Int64?
    let promptEvalCount: Int?
    let evalCount: Int?

    enum CodingKeys: String, CodingKey {
        case model, response, done
        case totalDuration = "total_duration"
        case loadDuration = "load_duration"
        case promptEvalCount = "prompt_eval_count"
        case evalCount = "eval_count"
    }
}

struct ModelsResponse: Codable {
    let models: [OllamaModel]
}

public struct OllamaModel: Codable, Sendable, Identifiable {
    public let name: String
    public let modifiedAt: String
    public let size: Int64

    public var id: String { name }

    /// Human-readable size
    public var sizeFormatted: String {
        let gb = Double(size) / 1_000_000_000
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        } else {
            let mb = Double(size) / 1_000_000
            return String(format: "%.0f MB", mb)
        }
    }

    /// Display name without tag
    public var displayName: String {
        if let colonIndex = name.firstIndex(of: ":") {
            return String(name[..<colonIndex])
        }
        return name
    }

    enum CodingKeys: String, CodingKey {
        case name
        case modifiedAt = "modified_at"
        case size
    }
}

// MARK: - Errors

public enum OllamaError: Error, LocalizedError {
    case connectionRefused
    case invalidResponse
    case serverError(Int)
    case modelNotFound(String)
    case timeout
    case decodingError(Error)

    public var errorDescription: String? {
        switch self {
        case .connectionRefused:
            return "Cannot connect to Ollama. Make sure it's running with: ollama serve"
        case .invalidResponse:
            return "Invalid response from Ollama server"
        case .serverError(let code):
            return "Ollama server error (HTTP \(code))"
        case .modelNotFound(let model):
            return "Model '\(model)' not found. Install with: ollama pull \(model)"
        case .timeout:
            return "Request timed out. The model may be loading or the text is too long."
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        }
    }
}
