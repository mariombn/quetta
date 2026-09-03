//
//  CodexBackendClient.swift
//  quetta
//
//  Streaming text client for the ChatGPT/Codex subscription backend
//  (Responses API shape over SSE). Sends only transcribed text — never audio —
//  and never logs meeting content.
//

import Foundation

nonisolated final class CodexBackendClient: @unchecked Sendable {

    static let endpoint = URL(string: "https://chatgpt.com/backend-api/codex/responses")!

    /// Streams output-text deltas for a single-turn request.
    func streamText(
        instructions: String,
        userText: String,
        model: String,
        tokens: CodexOAuthService.Tokens
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: Self.endpoint)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("responses=experimental", forHTTPHeaderField: "OpenAI-Beta")
                    request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
                    request.setValue(UUID().uuidString, forHTTPHeaderField: "session_id")
                    if let accountID = tokens.accountID {
                        request.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id")
                    }

                    // Mirrors the shape the official Codex CLI sends; the task
                    // prompt travels as a developer message in `input`.
                    let body: [String: Any] = [
                        "model": model,
                        "instructions": Self.baseInstructions,
                        "input": [
                            [
                                "type": "message",
                                "role": "developer",
                                "content": [["type": "input_text", "text": instructions]],
                            ],
                            [
                                "type": "message",
                                "role": "user",
                                "content": [["type": "input_text", "text": userText]],
                            ],
                        ],
                        "tools": [],
                        "tool_choice": "auto",
                        "parallel_tool_calls": false,
                        "store": false,
                        "stream": true,
                        "include": ["reasoning.encrypted_content"],
                        "prompt_cache_key": UUID().uuidString,
                        "reasoning": ["effort": "low", "summary": "auto"],
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw ProviderError.network }
                    switch http.statusCode {
                    case 200...299:
                        break
                    case 401, 403:
                        throw ProviderError.authentication
                    case 429:
                        throw ProviderError.rateLimited
                    default:
                        // Read the error body — it names the exact problem
                        // (invalid model, bad field, etc.), which the UI surfaces.
                        var detail = ""
                        for try await line in bytes.lines {
                            detail += line
                            if detail.count > 2000 { break }
                        }
                        throw ProviderError.message("HTTP \(http.statusCode): \(Self.compactErrorMessage(from: detail))")
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = event["type"] as? String else { continue }

                        switch type {
                        case "response.output_text.delta":
                            if let delta = event["delta"] as? String, !delta.isEmpty {
                                continuation.yield(delta)
                            }
                        case "response.completed":
                            continuation.finish()
                            return
                        case "response.failed", "error":
                            let message = Self.errorMessage(from: event)
                            throw ProviderError.message(message)
                        default:
                            continue
                        }
                    }
                    continuation.finish()
                } catch let error as ProviderError {
                    continuation.finish(throwing: error)
                } catch is CancellationError {
                    continuation.finish(throwing: ProviderError.cancelled)
                } catch {
                    continuation.finish(throwing: ProviderError.network)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Base instructions for the subscription backend. The task-specific prompt
    /// travels as a developer message in `input`.
    static let baseInstructions =
        "You are a helpful assistant. Follow the developer message precisely and respond with the requested content only."

    /// Extracts a short human-readable message from an error response body.
    static func compactErrorMessage(from body: String) -> String {
        if let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                return message
            }
            if let detail = json["detail"] as? String {
                return detail
            }
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unknown error" : String(trimmed.prefix(300))
    }

    private static func errorMessage(from event: [String: Any]) -> String {
        if let response = event["response"] as? [String: Any],
           let error = response["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        if let message = (event["error"] as? [String: Any])?["message"] as? String {
            return message
        }
        return String(localized: "error.provider.invalidResponse")
    }
}
