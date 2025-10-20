#if USE_REMOTE_DEPS && canImport(Supabase)
import Foundation
import Supabase
import WhatsThatDomain
import WhatsThatShared

public enum DiscoveryAnalysisClientError: LocalizedError {
    case unauthenticated
    case invalidResponse
    case unexpectedStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "You need to sign in before creating a discovery."
        case .invalidResponse:
            return "The analysis service returned an unexpected response."
        case let .unexpectedStatus(code):
            return "The analysis service returned status code \(code)."
        }
    }
}

public final class SupabaseDiscoveryAnalysisClient: DiscoveryAnalysisClient {
    private let client: SupabaseClient
    private let configuration: AppConfiguration
    private let urlSession: URLSession
    private let tokenRegex = try? NSRegularExpression(
        pattern: #"\"text\"\s*:\s*\"((?:\\.|[^"\\])*)\""#,
        options: []
    )
    #if DEBUG
    private let isDebugLoggingEnabled = true
    #else
    private let isDebugLoggingEnabled = false
    #endif

    public init(
        client: SupabaseClient,
        configuration: AppConfiguration,
        urlSession: URLSession = .shared
    ) {
        self.client = client
        self.configuration = configuration
        self.urlSession = urlSession
    }

    public func startAnalysis(
        payload: DiscoveryAnalysisPayload,
        sessionId: UUID,
        cancellationHandler: @escaping @Sendable () async -> Void
    ) -> AsyncThrowingStream<DiscoveryAnalysisEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try await makeRequest(with: payload, sessionId: sessionId)
                    let (bytes, response) = try await urlSession.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw DiscoveryAnalysisClientError.invalidResponse
                    }

                    guard (200..<300).contains(httpResponse.statusCode) else {
                        throw DiscoveryAnalysisClientError.unexpectedStatus(httpResponse.statusCode)
                    }

                    var buffer = Data()
                    var streamedText = ""
                    var didEmitMetadata = false

                    for try await chunk in bytes {
                        buffer.append(chunk)
                        try await parseAvailableEvents(
                            from: &buffer,
                            continuation: continuation,
                            streamedText: &streamedText,
                            didEmitMetadata: &didEmitMetadata
                        )
                    }

                    if !buffer.isEmpty {
                        try await parseAvailableEvents(
                            from: &buffer,
                            continuation: continuation,
                            streamedText: &streamedText,
                            didEmitMetadata: &didEmitMetadata
                        )
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { termination in
                task.cancel()
                if case .cancelled = termination {
                    Task {
                        await cancellationHandler()
                    }
                }
            }
        }
    }

    private func makeRequest(with payload: DiscoveryAnalysisPayload, sessionId: UUID) async throws -> URLRequest {
        guard
            let configurationURL = configuration.supabaseURL
        else {
            throw DiscoveryAnalysisClientError.invalidResponse
        }

        guard let accessToken = client.auth.currentSession?.accessToken else {
            throw DiscoveryAnalysisClientError.unauthenticated
        }

        let functionsURL = Self.functionsBaseURL(from: configurationURL).appendingPathComponent("ask-ai-v7")

        var request = URLRequest(url: functionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(sessionId.uuidString, forHTTPHeaderField: "X-Request-ID")

        var body: [String: Any] = [
            "base64Image": payload.base64Image
        ]

        if let location = payload.location {
            body["location"] = [
                "latitude": location.latitude,
                "longitude": location.longitude,
                "country": location.country as Any,
                "locality": location.locality as Any,
                "streetName": location.streetName as Any,
                "closestPlace": location.closestPlace as Any
            ]
        }

        if let customContext = payload.customContext {
            body["customContext"] = customContext
        }

        if let pushToken = payload.pushToken {
            body["pushToken"] = pushToken
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        return request
    }

    private static func functionsBaseURL(from supabaseURL: URL) -> URL {
        var components = URLComponents(url: supabaseURL, resolvingAgainstBaseURL: false)
        components?.host = supabaseURL
            .host?
            .replacingOccurrences(of: ".supabase.co", with: ".functions.supabase.co")
        return components?.url ?? supabaseURL
    }

    private func parseAvailableEvents(
        from buffer: inout Data,
        continuation: AsyncThrowingStream<DiscoveryAnalysisEvent, Error>.Continuation,
        streamedText: inout String,
        didEmitMetadata: inout Bool
    ) async throws {
        let delimiter = Data("\n\n".utf8)

        while let range = buffer.range(of: delimiter) {
            let eventData = buffer.subdata(in: 0..<range.lowerBound)
            buffer.removeSubrange(0..<range.upperBound)

            guard let event = parseEvent(from: eventData) else {
                continue
            }

            continuation.yield(event)

            // Opportunistically emit a metadata event as soon as we can parse it from
            // the token stream, mirroring the RN client's behavior. This lets the UI
            // show title/shortDescription immediately rather than waiting for the server
            // 'metadata' event (which arrives much later).
            if case let .token(tokenText) = event {
                streamedText.append(tokenText)
                if didEmitMetadata == false {
                    let parser = DiscoveryAnalysisParser()
                    if let content = parser.parse(streamedText),
                       let title = content.metadata?.title, !title.isEmpty,
                       let short = content.metadata?.shortDescription, !short.isEmpty {
                        continuation.yield(.metadata(title: title, shortDescription: short))
                        didEmitMetadata = true
                    }
                }
            }
        }
    }

    private func parseEvent(from data: Data) -> DiscoveryAnalysisEvent? {
        guard let payload = String(data: data, encoding: .utf8) else {
            return nil
        }

        var eventType = "message"
        var dataLines: [String] = []

        for line in payload.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("event:") {
                eventType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                dataLines.append(String(line.dropFirst(5)))
            }
        }

        let dataString = dataLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        switch eventType {
        case "status":
            if let message = parseMessage(from: dataString) {
                debugLog("status", dataString)
                return .status(message)
            }
        case "metadata":
            if let info = parseDictionary(from: dataString) {
                let title = (info["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let short = (info["shortDescription"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                debugLog("metadata", dataString)
                return .metadata(title: title, shortDescription: short)
            } else {
                debugLog("metadata", dataString)
                return .metadata(title: nil, shortDescription: nil)
            }
        case "token":
            let tokens = parseTokenText(from: dataString)
            if tokens.isEmpty {
                debugLog("token(raw)", dataString)
                return .token(dataString)
            } else {
                let combined = tokens.joined()
                debugLog("token(parsed)", combined)
                return .token(tokens.joined())
            }
        case "complete":
            if let info = parseDictionary(from: dataString),
               let identifier = parseIdentifier(from: info["discoveryId"]) {
                let systemVersion = info["systemPromptVersion"] as? String
                let userVersion = info["userPromptVersion"] as? String
                return .complete(discoveryId: identifier, systemPromptVersion: systemVersion, userPromptVersion: userVersion)
            }
        case "error":
            if let message = parseMessage(from: dataString) {
                return .error(message: message)
            }
        case "end":
            return .end
        default:
            break
        }

        return nil
    }

    private func debugLog(_ event: String, _ payload: String) {
        guard isDebugLoggingEnabled else { return }
        print("[SupabaseDiscoveryAnalysisClient] event=\(event) payload=\(payload)")
    }

    private func parseTokenText(from data: String) -> [String] {
        if let dictionary = parseDictionary(from: data) {
            if let text = dictionary["text"] as? String {
                return [text]
            }
            if
                let choices = dictionary["choices"] as? [[String: Any]],
                let firstChoice = choices.first,
                let delta = firstChoice["delta"] as? [String: Any],
                let content = delta["content"] as? String
            {
                return [content]
            }
        }

        guard let tokenRegex else {
            return data.isEmpty ? [] : [data]
        }

        let range = NSRange(location: 0, length: (data as NSString).length)
        var results: [String] = []
        tokenRegex.enumerateMatches(in: data, options: [], range: range) { match, _, _ in
            guard let match,
                  match.numberOfRanges >= 2
            else {
                return
            }
            let captured = (data as NSString).substring(with: match.range(at: 1))
            if let decoded = decodeJSONString(captured) {
                results.append(decoded)
            } else {
                results.append(captured)
            }
        }

        if results.isEmpty, !data.isEmpty {
            results.append(data)
        }

        return results
    }

    private func decodeJSONString(_ fragment: String) -> String? {
        let wrapped = "\"\(fragment)\""
        guard let wrappedData = wrapped.data(using: .utf8) else {
            return nil
        }

        if let decoded = try? JSONSerialization.jsonObject(with: wrappedData, options: []) as? String {
            return decoded
        }

        return nil
    }

    private func parseMessage(from data: String) -> String? {
        if let dictionary = parseDictionary(from: data) {
            if let message = dictionary["message"] as? String {
                return message
            } else if let status = dictionary["status"] as? String {
                return status
            }
        }
        return data.isEmpty ? nil : data
    }

    private func parseDictionary(from data: String) -> [String: Any]? {
        guard let rawData = data.data(using: .utf8) else {
            return nil
        }

        if let object = try? JSONSerialization.jsonObject(with: rawData, options: []),
           let dictionary = object as? [String: Any] {
            return dictionary
        }
        return nil
    }

    private func parseIdentifier(from value: Any?) -> Int64? {
        if let identifier = value as? Int64 {
            return identifier
        }

        if let number = value as? NSNumber {
            return number.int64Value
        }

        if let identifier = value as? Int {
            return Int64(identifier)
        }

        if let identifier = value as? String,
           let intValue = Int64(identifier) {
            return intValue
        }

        return nil
    }
}
#endif
