//
//  ProviderConfiguration.swift
//  quetta
//
//  Non-secret metadata describing a configured AI provider. Secrets (API keys,
//  OAuth tokens) live only in the Keychain, keyed by this configuration's id.
//

import Foundation
import SwiftData

@Model
final class ProviderConfiguration {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var displayName: String
    var isEnabled: Bool
    var createdAt: Date

    /// Non-secret configuration such as the selected model or a future local URL.
    var modelName: String?
    var baseURLString: String?

    /// Set when the provider requires re-authentication (e.g. expired token / bad key).
    var requiresAttention: Bool

    init(
        id: UUID = UUID(),
        kind: ProviderKind,
        displayName: String,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        modelName: String? = nil,
        baseURLString: String? = nil,
        requiresAttention: Bool = false
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.displayName = displayName
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.modelName = modelName
        self.baseURLString = baseURLString
        self.requiresAttention = requiresAttention
    }

    var kind: ProviderKind {
        get { ProviderKind(rawValue: kindRaw) ?? .openAI }
        set { kindRaw = newValue.rawValue }
    }

    /// Keychain account identifier for this configuration's primary secret.
    var keychainAccount: String { "provider.\(id.uuidString)" }
}
