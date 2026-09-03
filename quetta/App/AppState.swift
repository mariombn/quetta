//
//  AppState.swift
//  quetta
//
//  Constructs and owns the shared services and the session coordinator, and wires
//  the floating panel content. Injected into the SwiftUI environment.
//

import Foundation
import SwiftUI
import SwiftData

@MainActor
@Observable
final class AppState {

    let container: ModelContainer
    let preferences: AppPreferences
    let permissions: PermissionService
    let connectivity: ConnectivityService
    let notifications: NotificationService
    let registry: AIProviderRegistry
    let panel: FloatingPanelController
    let coordinator: AppCoordinator

    init(container: ModelContainer, secretStore: SecretStore = KeychainStore()) {
        self.container = container
        let preferences = AppPreferences()
        let permissions = PermissionService()
        let connectivity = ConnectivityService()
        let notifications = NotificationService()
        let registry = AIProviderRegistry(secretStore: secretStore)
        let panel = FloatingPanelController()

        self.preferences = preferences
        self.permissions = permissions
        self.connectivity = connectivity
        self.notifications = notifications
        self.registry = registry
        self.panel = panel

        let coordinator = AppCoordinator(
            modelContext: container.mainContext,
            preferences: preferences,
            permissions: permissions,
            connectivity: connectivity,
            notifications: notifications,
            registry: registry,
            panel: panel
        )
        self.coordinator = coordinator

        coordinator.panelContent = { [weak coordinator, weak preferences, container] in
            guard let coordinator, let preferences else { return AnyView(EmptyView()) }
            return AnyView(
                FloatingPanelView()
                    .environment(coordinator)
                    .environment(preferences)
                    .modelContainer(container)
                    .environment(\.locale, Locale(identifier: preferences.localeIdentifierForUI ?? Locale.current.identifier))
                    .preferredColorScheme(preferences.colorScheme)
            )
        }
    }
}
