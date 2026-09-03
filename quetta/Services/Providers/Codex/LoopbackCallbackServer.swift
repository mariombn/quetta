//
//  LoopbackCallbackServer.swift
//  quetta
//
//  Minimal loopback HTTP listener used exclusively to receive the OAuth
//  redirect (http://localhost:1455/auth/callback). It parses the query string
//  of the first matching GET request, answers with a small confirmation page,
//  and shuts down. Nothing else is served.
//

import Foundation
import Network

nonisolated final class LoopbackCallbackServer: @unchecked Sendable {

    private let port: UInt16
    private let path: String
    private let queue = DispatchQueue(label: "com.quetta.codex.callback")
    private let lock = NSLock()

    private var listener: NWListener?
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var connections: [NWConnection] = []

    init(port: UInt16, path: String) {
        self.port = port
        self.path = path
    }

    func start() throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw CodexOAuthService.LoginError.portInUse
        }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        // Bind to loopback only — never expose the listener beyond this machine.
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: nwPort)

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw CodexOAuthService.LoginError.portInUse
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                self?.fail(CodexOAuthService.LoginError.portInUse)
            }
        }
        listener.start(queue: queue)

        lock.lock()
        self.listener = listener
        lock.unlock()
    }

    func stop() {
        lock.lock()
        let listener = self.listener
        let connections = self.connections
        self.listener = nil
        self.connections = []
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        listener?.cancel()
        connections.forEach { $0.cancel() }
        continuation?.resume(throwing: CancellationError())
    }

    /// Waits for the OAuth redirect, returning its query parameters.
    func waitForCallback(timeout: TimeInterval) async throws -> [String: String] {
        try await withThrowingTaskGroup(of: [String: String].self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    self.lock.lock()
                    self.continuation = continuation
                    self.lock.unlock()
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw CodexOAuthService.LoginError.timeout
            }
            guard let result = try await group.next() else {
                throw CodexOAuthService.LoginError.timeout
            }
            group.cancelAll()
            return result
        }
    }

    // MARK: - Connection handling

    private func accept(_ connection: NWConnection) {
        lock.lock()
        connections.append(connection)
        lock.unlock()

        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            self.handle(request: request, on: connection)
        }
    }

    private func handle(request: String, on connection: NWConnection) {
        // First line: "GET /auth/callback?code=...&state=... HTTP/1.1"
        guard let firstLine = request.components(separatedBy: "\r\n").first else {
            respond(connection, status: "400 Bad Request", body: "Bad request")
            return
        }
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2, parts[0] == "GET",
              let components = URLComponents(string: parts[1]),
              components.path == path else {
            respond(connection, status: "404 Not Found", body: "Not found")
            return
        }

        var params: [String: String] = [:]
        for item in components.queryItems ?? [] {
            params[item.name] = item.value
        }

        respond(
            connection,
            status: "200 OK",
            body: "<html><body style=\"font-family:-apple-system;text-align:center;padding-top:80px\">" +
                  "<h2>Quetta</h2><p>Login concluído. Você pode fechar esta janela.<br>" +
                  "Sign-in complete. You can close this window.</p></body></html>"
        )

        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: params)
    }

    private func respond(_ connection: NWConnection, status: String, body: String) {
        let payload = Data(body.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\n" +
                   "Content-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func fail(_ error: Error) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: error)
    }
}
