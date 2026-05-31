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

    override init() {
        super.init()
        loadTokensFromKeychain()
    }

    // MARK: - Sign In

    func signIn() {
        isLoading = true
        error = nil

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

        // Open Google login in default browser
        NSWorkspace.shared.open(url)
    }

    func signOut() {
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
        userEmail = nil
        isAuthenticated = false
        deleteTokensFromKeychain()
    }

    // MARK: - Token Management

    func validAccessToken() async -> String? {
        if let token = accessToken, let expiry = tokenExpiry, expiry > Date() {
            return token
        }
        await refreshAccessToken()
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
            let socket = socket(AF_INET, SOCK_STREAM, 0)
            guard socket >= 0 else { continue }
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(port).bigEndian
            addr.sin_addr.s_addr = INADDR_ANY
            let bound = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            close(socket)
            if bound == 0 { return port }
        }
        return 8080
    }

    // MARK: - Keychain

    private let keychainService = "app.tabella.Eventually"

    private func saveTokensToKeychain() {
        if let t = accessToken  { saveToKeychain(key: "accessToken",  value: t) }
        if let t = refreshToken { saveToKeychain(key: "refreshToken", value: t) }
        if let e = tokenExpiry  { saveToKeychain(key: "tokenExpiry",  value: String(e.timeIntervalSince1970)) }
        if let e = userEmail    { saveToKeychain(key: "userEmail",    value: e) }
    }

    private func loadTokensFromKeychain() {
        accessToken  = loadFromKeychain(key: "accessToken")
        refreshToken = loadFromKeychain(key: "refreshToken")
        userEmail    = loadFromKeychain(key: "userEmail")
        if let s = loadFromKeychain(key: "tokenExpiry"), let t = Double(s) {
            tokenExpiry = Date(timeIntervalSince1970: t)
        }
        isAuthenticated = refreshToken != nil
    }

    private func deleteTokensFromKeychain() {
        ["accessToken", "refreshToken", "tokenExpiry", "userEmail"].forEach { deleteFromKeychain(key: $0) }
    }

    private func saveToKeychain(key: String, value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: value.data(using: .utf8)!,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
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
            <html><body style="font-family:system-ui;text-align:center;padding:60px;background:#1a1a1a;color:white">
            <h2>✓ Signed in successfully</h2>
            <p>You can close this tab and return to Eventually.</p>
            <script>window.close()</script>
            </body></html>
            """
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
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
