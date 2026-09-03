//
//  CodexOAuthTests.swift
//  quettaTests
//

import Testing
import Foundation
@testable import quetta

@Suite("Codex OAuth helpers")
struct CodexOAuthTests {

    @Test("PKCE challenge matches the RFC 7636 test vector")
    func pkceVector() {
        // Appendix B of RFC 7636.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let challenge = CodexOAuthService.codeChallenge(for: verifier)
        #expect(challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test("Random URL-safe strings avoid padding and unsafe characters")
    func randomURLSafe() {
        let value = CodexOAuthService.randomURLSafe(count: 64)
        #expect(!value.isEmpty)
        #expect(!value.contains("="))
        #expect(!value.contains("+"))
        #expect(!value.contains("/"))
    }

    @Test("Extracts the ChatGPT account id from an id_token")
    func accountIDFromJWT() throws {
        let payload: [String: Any] = [
            "sub": "user-123",
            "https://api.openai.com/auth": ["chatgpt_account_id": "acct-abc"],
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let token = "eyJhbGciOiJub25lIn0." + CodexOAuthService.base64URL(payloadData) + ".sig"
        #expect(CodexOAuthService.accountID(fromIDToken: token) == "acct-abc")
    }

    @Test("Returns nil for malformed id_tokens")
    func malformedJWT() {
        #expect(CodexOAuthService.accountID(fromIDToken: "not-a-jwt") == nil)
        #expect(CodexOAuthService.accountID(fromIDToken: "a.b") == nil)
    }

    @Test("Tokens persist and clear through the secret store")
    func tokenPersistence() throws {
        let store = FakeSecretStore()
        let service = CodexOAuthService(secretStore: store, account: "codex-test")
        #expect(service.storedTokens() == nil)

        let tokens = CodexOAuthService.Tokens(
            accessToken: "at",
            refreshToken: "rt",
            idToken: nil,
            accountID: "acct",
            expiresAt: Date().addingTimeInterval(3600)
        )
        try service.save(tokens)
        let loaded = service.storedTokens()
        #expect(loaded?.accessToken == "at")
        #expect(loaded?.refreshToken == "rt")
        #expect(loaded?.accountID == "acct")

        service.logout()
        #expect(service.storedTokens() == nil)
    }

    @Test("Codex provider advertises full capabilities when available")
    func codexCapabilities() {
        let provider = CodexOAuthProvider(
            id: UUID(),
            displayName: "Codex",
            oauth: CodexOAuthService(secretStore: FakeSecretStore(), account: "x")
        )
        #expect(CodexOAuthProvider.isAvailable)
        #expect(provider.capabilities.supportsSummary)
        #expect(provider.capabilities.supportsLiveTranslation)
        #expect(provider.capabilities.supportsStreamingTranslation)
        #expect(provider.capabilities.supportedLanguages.contains(.spanish))
    }

    @Test("Validation without stored tokens reports not configured")
    func validateWithoutTokens() async {
        let provider = CodexOAuthProvider(
            id: UUID(),
            displayName: "Codex",
            oauth: CodexOAuthService(secretStore: FakeSecretStore(), account: "y")
        )
        await #expect(throws: ProviderError.self) {
            try await provider.validateConfiguration()
        }
    }
}
