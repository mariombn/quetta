//
//  CodexOAuthService.swift
//  quetta
//
//  Self-contained OAuth (authorization code + PKCE) login for the personal
//  Codex/ChatGPT subscription provider (spec §8.2). The app performs its OWN
//  login in the user's browser and receives the callback on a local loopback
//  listener. Tokens live ONLY in the macOS Keychain and are refreshed here.
//
//  It never reads or depends on Pi Agent, the Codex CLI or the ChatGPT app,
//  and never extracts credentials from other applications.
//

import Foundation
import CryptoKit
import AppKit
import Network

nonisolated final class CodexOAuthService: @unchecked Sendable {

    // Public OAuth client used by OpenAI's official Codex sign-in flow.
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let authorizeURL = URL(string: "https://auth.openai.com/oauth/authorize")!
    static let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    static let callbackPort: UInt16 = 1455
    static let callbackPath = "/auth/callback"
    static var redirectURI: String { "http://localhost:\(callbackPort)\(callbackPath)" }

    struct Tokens: Codable, Sendable {
        var accessToken: String
        var refreshToken: String
        var idToken: String?
        var accountID: String?
        var expiresAt: Date
    }

    enum LoginError: LocalizedError {
        case portInUse
        case timeout
        case invalidCallback
        case exchangeFailed(String)

        var errorDescription: String? {
            switch self {
            case .portInUse: return String(localized: "error.codex.port")
            case .timeout: return String(localized: "error.codex.timeout")
            case .invalidCallback: return String(localized: "error.codex.callback")
            case .exchangeFailed(let detail): return detail
            }
        }
    }

    private let secretStore: SecretStore
    private let account: String

    init(secretStore: SecretStore, account: String) {
        self.secretStore = secretStore
        self.account = account
    }

    // MARK: - Token storage (Keychain only)

    func storedTokens() -> Tokens? {
        guard let json = (try? secretStore.read(account: account)) ?? nil,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Tokens.self, from: data)
    }

    func save(_ tokens: Tokens) throws {
        let data = try JSONEncoder().encode(tokens)
        guard let json = String(data: data, encoding: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try secretStore.save(json, account: account)
    }

    func logout() {
        try? secretStore.delete(account: account)
    }

    /// Returns valid tokens, refreshing them when close to expiry.
    func validTokens() async throws -> Tokens {
        guard let tokens = storedTokens() else { throw ProviderError.notConfigured }
        if tokens.expiresAt > Date().addingTimeInterval(120) {
            return tokens
        }
        return try await refresh(tokens)
    }

    // MARK: - Login

    /// Runs the full browser login. Returns the persisted tokens.
    @discardableResult
    func login() async throws -> Tokens {
        let verifier = Self.randomURLSafe(count: 64)
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomURLSafe(count: 32)

        let server = LoopbackCallbackServer(port: Self.callbackPort, path: Self.callbackPath)
        try server.start()
        defer { server.stop() }

        var comps = URLComponents(url: Self.authorizeURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: "openid profile email offline_access"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
        ]
        let url = comps.url!
        await MainActor.run { NSWorkspace.shared.open(url) }

        let params = try await server.waitForCallback(timeout: 300)
        guard params["state"] == state, let code = params["code"] else {
            throw LoginError.invalidCallback
        }

        let tokens = try await exchange(code: code, verifier: verifier)
        try save(tokens)
        return tokens
    }

    // MARK: - Token endpoint

    private func exchange(code: String, verifier: String) async throws -> Tokens {
        let form = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": Self.clientID,
            "code_verifier": verifier,
        ]
        let response = try await postForm(form)
        return try Self.tokens(from: response, fallbackRefreshToken: nil)
    }

    func refresh(_ tokens: Tokens) async throws -> Tokens {
        let form = [
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken,
            "client_id": Self.clientID,
            "scope": "openid profile email",
        ]
        do {
            let response = try await postForm(form)
            let refreshed = try Self.tokens(from: response, fallbackRefreshToken: tokens.refreshToken)
            try save(refreshed)
            return refreshed
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.authentication
        }
    }

    private func postForm(_ form: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form
            .map { "\($0.key)=\(Self.formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProviderError.network }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 400 {
                throw ProviderError.authentication
            }
            throw LoginError.exchangeFailed("HTTP \(http.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse
        }
        return json
    }

    private static func tokens(from json: [String: Any], fallbackRefreshToken: String?) throws -> Tokens {
        guard let accessToken = json["access_token"] as? String else {
            throw ProviderError.invalidResponse
        }
        guard let refreshToken = (json["refresh_token"] as? String) ?? fallbackRefreshToken else {
            throw ProviderError.invalidResponse
        }
        let idToken = json["id_token"] as? String
        let expiresIn = (json["expires_in"] as? Double) ?? 3600
        return Tokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            idToken: idToken,
            accountID: idToken.flatMap(Self.accountID(fromIDToken:)),
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
    }

    // MARK: - PKCE / JWT helpers (static for testability)

    static func randomURLSafe(count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return base64URL(Data(bytes))
    }

    static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(digest))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Extracts the ChatGPT account id from the id_token JWT claims.
    static func accountID(fromIDToken idToken: String) -> String? {
        let parts = idToken.components(separatedBy: ".")
        guard parts.count >= 2 else { return nil }
        var payload = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let auth = json["https://api.openai.com/auth"] as? [String: Any]
        return auth?["chatgpt_account_id"] as? String
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
