import AppKit
import CryptoKit
import Foundation
import KoeCore

/// Google OAuth service for Gemini API access (same method as Gemini CLI)
@MainActor
public final class GoogleAuthService: NSObject, ObservableObject {
    public static let shared = GoogleAuthService()

    // MARK: - Published State

    @Published public private(set) var isAuthenticated: Bool = false
    @Published public private(set) var isAuthenticating: Bool = false
    @Published public private(set) var userEmail: String?

    // MARK: - OAuth Configuration
    // Note: OAuth is deprecated - use GeminiService with API key instead
    // These placeholders are kept for backwards compatibility

    private let clientId = ProcessInfo.processInfo.environment["GOOGLE_CLIENT_ID"] ?? ""
    private let clientSecret = ProcessInfo.processInfo.environment["GOOGLE_CLIENT_SECRET"] ?? ""
    private let redirectUri = "http://localhost:45289"

    private let authUrl = "https://accounts.google.com/o/oauth2/v2/auth"
    private let tokenUrl = "https://oauth2.googleapis.com/token"

    // Scopes must match Gemini CLI exactly
    private let scopes = [
        "https://www.googleapis.com/auth/cloud-platform",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
    ]

    // MARK: - Token Storage

    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiry: Date?

    private var authDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini")
    }

    private var authFile: URL {
        authDir.appendingPathComponent("oauth_creds.json")
    }

    private var localServer: GeminiOAuthServer?
    private let logger = KoeLogger.refinement

    // MARK: - Initialization

    override private init() {
        super.init()
        loadTokens()
    }

    // MARK: - Public API

    /// Start the OAuth flow (same as Gemini CLI)
    public func signIn() async throws {
        guard !isAuthenticating else { return }

        isAuthenticating = true
        defer { isAuthenticating = false }

        let state = generateState()

        // Build authorization URL
        var components = URLComponents(string: authUrl)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]

        guard let authURL = components.url else {
            throw GeminiAuthError.invalidURL
        }

        // Start local server to receive callback
        localServer = GeminiOAuthServer(port: 45289)
        try await localServer?.start()

        // Open browser
        logger.info("Opening Google OAuth URL for Gemini")
        NSWorkspace.shared.open(authURL)

        // Wait for callback
        guard let (code, receivedState) = try await localServer?.waitForCode() else {
            throw GeminiAuthError.authorizationFailed("No authorization code received")
        }

        await localServer?.stop()
        localServer = nil

        // Verify state
        guard receivedState == state else {
            throw GeminiAuthError.stateMismatch
        }

        // Exchange code for tokens
        try await exchangeCodeForTokens(code: code)

        logger.info("Gemini OAuth completed successfully")
    }

    /// Sign out and clear tokens
    public func signOut() {
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
        userEmail = nil
        isAuthenticated = false
        clearStoredTokens()
        logger.info("Signed out of Gemini")
    }

    /// Get a valid access token (refreshing if needed)
    public func getAccessToken() async throws -> String {
        // Check if token is valid
        if let token = accessToken, let expiry = tokenExpiry, expiry > Date() {
            return token
        }

        // Try to refresh
        if let refresh = refreshToken {
            try await refreshAccessToken(refreshToken: refresh)
            if let token = accessToken {
                return token
            }
        }

        throw GeminiAuthError.notAuthenticated
    }

    // MARK: - Private Methods

    private func exchangeCodeForTokens(code: String) async throws {
        var request = URLRequest(url: URL(string: tokenUrl)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectUri,
            "client_id": clientId,
            "client_secret": clientSecret,
        ]
        request.httpBody = body.map {
            "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)"
        }
        .joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GeminiAuthError.tokenExchangeFailed(errorBody)
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = tokenResponse.accessToken
        refreshToken = tokenResponse.refreshToken ?? refreshToken
        tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn - 60))
        isAuthenticated = true

        saveTokens()

        // Fetch user email
        try await fetchUserEmail()
    }

    private func refreshAccessToken(refreshToken: String) async throws {
        var request = URLRequest(url: URL(string: tokenUrl)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientId,
            "client_secret": clientSecret,
        ]
        request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            // Refresh token invalid, need to re-authenticate
            signOut()
            throw GeminiAuthError.refreshFailed
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = tokenResponse.accessToken
        tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn - 60))

        saveTokens()
    }

    private func fetchUserEmail() async throws {
        guard let token = accessToken else { return }

        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        let userInfo = try JSONDecoder().decode(UserInfo.self, from: data)
        userEmail = userInfo.email
    }

    private func generateState() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Token Persistence (compatible with Gemini CLI)

    private func saveTokens() {
        do {
            try FileManager.default.createDirectory(at: authDir, withIntermediateDirectories: true)

            let tokens = StoredTokens(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: tokenExpiry?.ISO8601Format(),
                email: userEmail
            )
            let data = try JSONEncoder().encode(tokens)
            try data.write(to: authFile)

            // Set secure permissions (600)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authFile.path)
        } catch {
            logger.error("Failed to save tokens: \(error)")
        }
    }

    private func loadTokens() {
        guard FileManager.default.fileExists(atPath: authFile.path) else { return }

        do {
            let data = try Data(contentsOf: authFile)
            let tokens = try JSONDecoder().decode(StoredTokens.self, from: data)

            accessToken = tokens.accessToken
            refreshToken = tokens.refreshToken
            userEmail = tokens.email

            if let expiresAt = tokens.expiresAt {
                let formatter = ISO8601DateFormatter()
                tokenExpiry = formatter.date(from: expiresAt)
            }

            isAuthenticated = refreshToken != nil
        } catch {
            logger.error("Failed to load tokens: \(error)")
        }
    }

    private func clearStoredTokens() {
        try? FileManager.default.removeItem(at: authFile)
    }
}

// MARK: - Supporting Types

public enum GeminiAuthError: LocalizedError {
    case invalidURL
    case authorizationFailed(String)
    case stateMismatch
    case tokenExchangeFailed(String)
    case refreshFailed
    case notAuthenticated

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid authorization URL"
        case .authorizationFailed(let reason):
            return "Authorization failed: \(reason)"
        case .stateMismatch:
            return "State mismatch - possible security issue"
        case .tokenExchangeFailed(let reason):
            return "Token exchange failed: \(reason)"
        case .refreshFailed:
            return "Failed to refresh token"
        case .notAuthenticated:
            return "Not authenticated"
        }
    }
}

private struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

private struct UserInfo: Codable {
    let email: String
}

private struct StoredTokens: Codable {
    let accessToken: String?
    let refreshToken: String?
    let expiresAt: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case email
    }
}

// MARK: - Local OAuth Server

/// Simple HTTP server to receive OAuth callback (port 45289 like Gemini CLI)
actor GeminiOAuthServer {
    private let port: UInt16
    private var listener: Task<Void, Error>?
    private var continuation: CheckedContinuation<(String, String)?, Error>?
    private var socket: Int32 = -1

    init(port: UInt16) {
        self.port = port
    }

    func start() async throws {
        socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else {
            throw GeminiAuthError.authorizationFailed("Failed to create socket")
        }

        var opt: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            close(socket)
            throw GeminiAuthError.authorizationFailed("Failed to bind to port \(port)")
        }

        listen(socket, 1)
    }

    func waitForCode() async throws -> (String, String)? {
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont

            Task {
                // Accept connection
                var clientAddr = sockaddr_in()
                var clientAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                let clientSocket = withUnsafeMutablePointer(to: &clientAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        accept(self.socket, $0, &clientAddrLen)
                    }
                }

                guard clientSocket >= 0 else {
                    self.continuation?.resume(returning: nil)
                    self.continuation = nil
                    return
                }

                // Read request
                var buffer = [CChar](repeating: 0, count: 4096)
                let bytesRead = read(clientSocket, &buffer, buffer.count - 1)

                var code: String?
                var state: String?

                if bytesRead > 0 {
                    let request = String(cString: buffer)

                    // Parse code from query string
                    if let codeRange = request.range(of: "code=") {
                        let afterCode = request[codeRange.upperBound...]
                        if let endRange = afterCode.range(of: "&") ?? afterCode.range(of: " ")
                            ?? afterCode.range(of: "\r")
                        {
                            code = String(afterCode[..<endRange.lowerBound])
                        }
                    }

                    // Parse state from query string
                    if let stateRange = request.range(of: "state=") {
                        let afterState = request[stateRange.upperBound...]
                        if let endRange = afterState.range(of: "&") ?? afterState.range(of: " ")
                            ?? afterState.range(of: "\r")
                        {
                            state = String(afterState[..<endRange.lowerBound])
                        }
                    }
                }

                // Send success response
                let html = """
                    <html>
                    <body style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; text-align: center; padding: 50px; background: #1a1a2e; color: white;">
                        <h1 style="color: #4ade80;">Authentication Successful!</h1>
                        <p>You can close this window and return to Koe.</p>
                    </body>
                    </html>
                    """
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n\(html)"
                _ = response.withCString { write(clientSocket, $0, strlen($0)) }

                close(clientSocket)

                if let code = code, let state = state {
                    self.continuation?.resume(returning: (code, state))
                } else {
                    self.continuation?.resume(returning: nil)
                }
                self.continuation = nil
            }
        }
    }

    func stop() async {
        if socket >= 0 {
            close(socket)
            socket = -1
        }
    }
}
