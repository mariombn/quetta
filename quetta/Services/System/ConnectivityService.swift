//
//  ConnectivityService.swift
//  quetta
//
//  Monitors network availability. The product requires connectivity to start or
//  continue a session (spec §3.6). Emits changes for the coordinator to react.
//

import Foundation
import Network

@MainActor
@Observable
final class ConnectivityService {

    private(set) var isConnected: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.quetta.connectivity")

    /// Called whenever connectivity transitions (true = became connected).
    var onChange: ((Bool) -> Void)?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in
                self?.apply(connected)
            }
        }
        monitor.start(queue: queue)
    }

    private func apply(_ connected: Bool) {
        guard connected != isConnected else { return }
        isConnected = connected
        onChange?(connected)
    }

    deinit {
        monitor.cancel()
    }
}
