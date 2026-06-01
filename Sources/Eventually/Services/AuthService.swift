import Foundation
import Security
import AppKit
import CryptoKit
import Network

@MainActor
class AuthService: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var userEmail: String?
    @Published var isLoading = false
    @Published var error: String?

    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiry: Date?

    private var clientId: String { GoogleConfig.clientId }
    private var clientSecret: String { GoogleConfig.clientSecret }
    private let scope = "https://www.googleapis.com/auth/tasks https://www.googleapis.com/auth/userinfo.email"
    private let authEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    private let tokenEndpoint = "https://oauth2.googleapis.com/token"

    private var codeVerifier: String?
    private var localServer: LocalCallbackServer?
    private var activeObserver: NSObjectProtocol?
    private var didReceiveCallback = false

    override init() {
        super.init()
        loadTokensFromKeychain()
    }

    deinit {
        if let observer = activeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Sign In

    func signIn() {
        // Tear down any previous in-flight attempt so re-tapping restarts cleanly
        cancelSignIn(resetLoading: false)

        isLoading = true
        error = nil
        didReceiveCallback = false

        let verifier = generateCodeVerifier()
        codeVerifier = verifier
        let challenge = generateCodeChallenge(from: verifier)

        // Pick a random available port
        let port = availablePort()
        let redirectUri = "http://localhost:\(port)"

        var components = URLComponents(string: authEndpoint)!
        components.queryItems = [
            .init(name: "client_id", value: clientId),
            .init(name: "redirect_uri", value: redirectUri),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scope),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]

        guard let url = components.url else {
            isLoading = false
            return
        }

        // Start local server to catch the redirect
        localServer = LocalCallbackServer(port: port)
        localServer?.start { [weak self] code in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.didReceiveCallback = true
                self.localServer?.stop()
                self.localServer = nil

                guard let code else {
                    self.isLoading = false
                    self.error = "Authorization cancelled"
                    return
                }

                await self.exchangeCode(code, redirectUri: redirectUri)
                self.isLoading = false
            }
        }

        // If the user closes the browser tab without finishing, the loopback
        // server never fires. Detect their return to the app and reset the
        // spinner so they can retry, after a short grace for the token exchange.
        observeReturnToApp()

        // Open Google login in default browser
        NSWorkspace.shared.open(url)
    }

    /// Watches for the app regaining focus mid-sign-in. If the user comes back
    /// without having completed the flow, reset the loading state.
    private func observeReturnToApp() {
        if let observer = activeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isLoading else { return }
                // Grace period: the callback may still be exchanging the code
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if self.isLoading && !self.didReceiveCallback {
                    self.cancelSignIn(resetLoading: true)
                }
            }
        }
    }

    /// Cancel an in-flight sign-in attempt and tear down its resources.
    func cancelSignIn(resetLoading: Bool) {
        localServer?.stop()
        localServer = nil
        if let observer = activeObserver {
            NotificationCenter.default.removeObserver(observer)
            activeObserver = nil
        }
        if resetLoading {
            isLoading = false
        }
    }

    func signOut() {
        // Cancel in-flight refresh to prevent re-authentication
        refreshInFlight?.cancel()
        refreshInFlight = nil

        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
        userEmail = nil
        codeVerifier = nil
        error = nil
        didReceiveCallback = false
        isAuthenticated = false
        deleteTokensFromKeychain()
    }

    // MARK: - Token Management

    /// In-flight refresh, shared by concurrent callers so N expired-token
    /// requests trigger exactly one refresh (avoids refresh-token reuse races).
    private var refreshInFlight: Task<Void, Never>?

    func validAccessToken() async -> String? {
        // Require 5s buffer to avoid mid-request expiry
        if let token = accessToken, let expiry = tokenExpiry, expiry > Date().addingTimeInterval(5) {
            return token
        }
        // Coalesce concurrent refresh requests: create exactly one Task,
        // all callers await the same Task then read the updated accessToken.
        // Capture a local reference before awaiting to prevent force-unwrap crash
        // if another caller nils out refreshInFlight between our check and our await.
        if refreshInFlight == nil {
            refreshInFlight = Task { await self.refreshAccessToken() }
        }
        let inFlight = refreshInFlight
        await inFlight?.value
        refreshInFlight = nil
        return accessToken
    }

    private func exchangeCode(_ code: String, redirectUri: String) async {
        guard let verifier = codeVerifier else { return }

        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "code": code,
            "client_id": clientId,
            "client_secret": clientSecret,
            "redirect_uri": redirectUri,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ]
        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(TokenResponse.self, from: data)
            accessToken = response.accessToken
            refreshToken = response.refreshToken ?? refreshToken
            tokenExpiry = Date().addingTimeInterval(Double(response.expiresIn - 60))
            saveTokensToKeychain()
            isAuthenticated = true
            await fetchUserEmail()
        } catch {
            self.error = "Sign in failed: \(error.localizedDescription)"
        }
    }

    private func refreshAccessToken() async {
        guard let refresh = refreshToken else {
            isAuthenticated = false
            return
        }

        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "refresh_token": refresh,
            "client_id": clientId,
            "client_secret": clientSecret,
            "grant_type": "refresh_token",
        ]
        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(TokenResponse.self, from: data)
            accessToken = response.accessToken
            tokenExpiry = Date().addingTimeInterval(Double(response.expiresIn - 60))
            saveTokensToKeychain()
            isAuthenticated = true
        } catch {
            // Clear refresh token to prevent infinite retry loop
            refreshToken = nil
            deleteTokensFromKeychain()
            isAuthenticated = false
        }
    }

    private func fetchUserEmail() async {
        guard let token = accessToken else { return }
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONDecoder().decode(UserInfo.self, from: data)
        else { return }
        userEmail = json.email
    }

    // MARK: - PKCE

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func availablePort() -> Int {
        // Try ports in range, fall back to 8080
        for port in 8080...8180 {
            let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else { continue }
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(port).bigEndian
            addr.sin_addr.s_addr = INADDR_ANY
            let bound = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            Darwin.close(fd)
            if bound == 0 { return port }
        }
        return 8080
    }

    // MARK: - Token Storage
    //
    // Tokens are stored in a user-only-readable file (chmod 0600) under
    // Application Support. This persists across rebuilds regardless of the
    // app's code signature — unlike the Keychain, whose ACL is tied to the
    // signing identity and re-prompts on every unsigned rebuild.
    //
    // The OAuth client secret is already embedded in the app binary, so a
    // local refresh token adds little marginal risk. For a signed release
    // build this can be swapped back to the Keychain.

    private struct StoredTokens: Codable {
        var accessToken: String?
        var refreshToken: String?
        var tokenExpiry: Double?
        var userEmail: String?
    }

    private var tokenFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Eventually", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("tokens.json")
    }

    private func saveTokensToKeychain() {
        let tokens = StoredTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenExpiry: tokenExpiry?.timeIntervalSince1970,
            userEmail: userEmail
        )
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        try? data.write(to: tokenFileURL, options: [.atomic, .completeFileProtection])
        // Restrict to owner read/write only
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenFileURL.path)
    }

    private func loadTokensFromKeychain() {
        guard let data = try? Data(contentsOf: tokenFileURL),
              let tokens = try? JSONDecoder().decode(StoredTokens.self, from: data) else {
            isAuthenticated = false
            return
        }
        accessToken = tokens.accessToken
        refreshToken = tokens.refreshToken
        userEmail = tokens.userEmail
        if let t = tokens.tokenExpiry { tokenExpiry = Date(timeIntervalSince1970: t) }
        isAuthenticated = refreshToken != nil
    }

    private func deleteTokensFromKeychain() {
        try? FileManager.default.removeItem(at: tokenFileURL)
    }
}

// MARK: - Local Callback Server

/// Minimal HTTP server that listens on localhost for the OAuth redirect
final class LocalCallbackServer {
    private let port: Int
    private var listener: NWListener?
    private var onCode: ((String?) -> Void)?

    init(port: Int) {
        self.port = port
    }

    func start(onCode: @escaping (String?) -> Void) {
        self.onCode = onCode
        let params = NWParameters.tcp
        guard let listener = try? NWListener(using: params, on: NWEndpoint.Port(integerLiteral: UInt16(port))) else {
            onCode(nil)
            return
        }
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let data, let request = String(data: data, encoding: .utf8) else {
                self?.onCode?(nil)
                return
            }

            // Parse "GET /?code=xxx HTTP/1.1"
            let code = request
                .components(separatedBy: "\r\n").first
                .flatMap { URL(string: "http://localhost" + ($0.components(separatedBy: " ").dropFirst().first ?? "")) }
                .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
                .queryItems?.first(where: { $0.name == "code" })?.value

            // Send a success page back to the browser
            let html = """
            <!DOCTYPE html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>Eventually</title>
            </head>
            <body style="margin:0;height:100vh;display:flex;align-items:center;justify-content:center;background:#1a1a1a;font-family:-apple-system,system-ui,sans-serif">
              <div style="text-align:center">
                <div style="width:64px;height:64px;margin:0 auto 24px;border-radius:16px;background:#4285F4;display:flex;align-items:center;justify-content:center">
                  <span style="font-size:34px;color:#1a1a1a">&#10003;</span>
                </div>
                <h2 style="color:#fff;font-weight:600;margin:0 0 8px">Signed in successfully</h2>
                <p style="color:#999;margin:0">You can close this tab and return to Eventually.</p>
              </div>
              <script>setTimeout(function(){window.close()},1200)</script>
            </body>
            </html>
            """
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })

            self?.onCode?(code)
        }
    }
}

// MARK: - Models

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
