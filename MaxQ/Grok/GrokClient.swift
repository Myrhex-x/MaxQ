//
//  GrokClient.swift
//  Max Q
//
//  Talks to the SpaceXAI API (api.x.ai) directly from this Mac with the user's own key. There is
//  no Max Q server in between: nobody but SpaceXAI sees the request, and the user's own account
//  pays for it.
//
//  Uses the Responses API, which carries the server-side tools Max Q relies on: `web_search`
//  (including the Grokipedia lookup, via an allowed-domain filter) and `x_search`.
//
//  Everything that comes back is untrusted model output: it is rendered as text, never executed.
//

import Foundation

// MARK: - Request

nonisolated enum GrokTool {
    case webSearch(allowedDomains: [String] = [], excludedDomains: [String] = [])
    case xSearch(allowedHandles: [String] = [], fromDate: String? = nil, toDate: String? = nil)

    nonisolated var json: [String: Any] {
        switch self {
        case let .webSearch(allowed, excluded):
            var tool: [String: Any] = ["type": "web_search"]
            // The API caps each list at 5 and rejects both at once.
            if !allowed.isEmpty {
                tool["filters"] = ["allowed_domains": Array(allowed.prefix(5))]
            } else if !excluded.isEmpty {
                tool["filters"] = ["excluded_domains": Array(excluded.prefix(5))]
            }
            return tool
        case let .xSearch(handles, from, to):
            var tool: [String: Any] = ["type": "x_search"]
            if !handles.isEmpty { tool["allowed_x_handles"] = Array(handles.prefix(10)) }
            if let from { tool["from_date"] = from }
            if let to { tool["to_date"] = to }
            return tool
        }
    }
}

nonisolated struct GrokMessage: Equatable {
    enum Role: String { case user, assistant, system }
    let role: Role
    let content: String
}

/// What a request is for. Not sent: it names the feature in the spending breakdown, and tells the
/// debug simulator what kind of answer to pretend.
nonisolated enum GrokPurpose: String, CaseIterable, Codable, Sendable {
    case answer, chat, check, research, article, video, brief, translate, agent, image, summary, rewrite

    var title: String {
        switch self {
        case .answer: String(localized: "Search answers")
        case .chat: String(localized: "Chat")
        case .check: String(localized: "Checks")
        case .research: String(localized: "Research")
        case .article: String(localized: "Questions about articles")
        case .video: String(localized: "Questions about videos")
        case .brief: String(localized: "Briefs")
        case .translate: String(localized: "Translation")
        case .agent: String(localized: "Agent")
        case .image: String(localized: "Images")
        case .summary: String(localized: "Summaries")
        case .rewrite: String(localized: "Rewriting")
        }
    }
}

/// A function Grok may call on the Mac (the agent's actions on a page).
nonisolated struct GrokFunction {
    let name: String
    let description: String
    /// JSON Schema of the arguments.
    let parameters: [String: Any]

    var json: [String: Any] {
        ["type": "function", "name": name, "description": description, "parameters": parameters]
    }
}

/// Grok asking to run one of the request's functions.
nonisolated struct GrokFunctionCall: Equatable, Sendable {
    let callID: String
    let name: String
    /// The arguments, as JSON.
    let arguments: String

    var argumentObject: [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any]) ?? [:]
    }
}

nonisolated struct GrokRequest {
    var model: String
    var instructions: String?
    var input: [GrokMessage]
    var tools: [GrokTool] = []
    /// Caps the agentic turns a tool-using answer may take (so a search can't run up the bill).
    var maxTurns: Int? = nil
    /// When set, the answer must be JSON matching this schema (name, schema).
    var jsonSchema: (name: String, schema: [String: Any])? = nil
    var maxOutputTokens: Int? = nil
    /// How much the model reasons first ("none", "low", "medium", "high"), for models that take it.
    var reasoningEffort: String? = nil
    /// Requests that share a beginning (a conversation) share this key, so SpaceXAI's prompt cache
    /// finds them and bills the repeated part at the cached price.
    var promptCacheKey: String? = nil
    /// What the request is for (not sent).
    var purpose: GrokPurpose = .answer
    /// Functions Grok may call on the Mac.
    var functions: [GrokFunction] = []
    /// Input items after the messages, as SpaceXAI returned them (an agent's earlier calls and their
    /// results, reasoning included), as a JSON array.
    var items: Data? = nil
    /// Extra output to ask for ("reasoning.encrypted_content", to carry reasoning between turns).
    var include: [String] = []
    /// An image to look at with the first message, as a data: or https URL.
    var imageURL: String? = nil

    nonisolated func body(stream: Bool) -> [String: Any] {
        var messages: [[String: Any]] = input.enumerated().map { index, message in
            if index == 0, let imageURL, message.role == .user {
                return ["role": "user", "content": [
                    ["type": "input_text", "text": message.content],
                    ["type": "input_image", "image_url": imageURL, "detail": "high"],
                ]]
            }
            return ["role": message.role.rawValue, "content": message.content]
        }
        if let items, let extra = try? JSONSerialization.jsonObject(with: items) as? [[String: Any]] {
            messages += extra
        }
        var body: [String: Any] = [
            "model": model,
            "input": messages,
            "stream": stream,
            // Don't keep the conversation on SpaceXAI's side; Max Q sends the history itself.
            "store": false,
        ]
        if let instructions { body["instructions"] = instructions }
        if !tools.isEmpty || !functions.isEmpty { body["tools"] = tools.map(\.json) + functions.map(\.json) }
        if !include.isEmpty { body["include"] = include }
        if let maxTurns { body["max_turns"] = maxTurns }
        if let maxOutputTokens { body["max_output_tokens"] = maxOutputTokens }
        if let reasoningEffort { body["reasoning"] = ["effort": reasoningEffort] }
        if let promptCacheKey { body["prompt_cache_key"] = promptCacheKey }
        if let jsonSchema {
            body["text"] = ["format": [
                "type": "json_schema",
                "name": jsonSchema.name,
                "strict": true,
                "schema": jsonSchema.schema,
            ]]
        }
        return body
    }
}

// MARK: - Models

nonisolated struct GrokModelInfo: Equatable, Codable, Identifiable {
    let id: String
    var aliases: [String] = []
    var contextLength: Int?
    /// USD per 1M input / output tokens. The API reports prices in 1e-10 USD per token.
    var inputPerMillion: Double?
    var outputPerMillion: Double?
    /// USD per 1M input tokens read from SpaceXAI's prompt cache.
    var cachedInputPerMillion: Double?
    /// The reasoning efforts the model accepts, when the list says (nil: not reported).
    var reasoningEfforts: [String]?
    var defaultReasoningEffort: String?

    nonisolated init(id: String) { self.id = id }

    nonisolated init?(json: [String: Any]) {
        guard let id = json["id"] as? String else { return nil }
        self.id = id
        aliases = json["aliases"] as? [String] ?? []
        contextLength = json["context_length"] as? Int
        inputPerMillion = Self.perMillion(json["prompt_text_token_price"])
        outputPerMillion = Self.perMillion(json["completion_text_token_price"])
        cachedInputPerMillion = Self.perMillion(json["cached_prompt_text_token_price"])
        if let capabilities = json["capabilities"] as? [String: Any] {
            reasoningEfforts = capabilities["reasoning_effort"] as? [String]
            defaultReasoningEffort = capabilities["default_reasoning_effort"] as? String
        }
    }

    nonisolated private static func perMillion(_ value: Any?) -> Double? {
        if let n = value as? Double { return n / 10_000 }
        if let n = value as? Int { return Double(n) / 10_000 }
        return nil
    }

    var priceLabel: String? {
        guard let input = inputPerMillion, let output = outputPerMillion else { return nil }
        return String(localized: "\(Money.usd(input)) in · \(Money.usd(output)) out per 1M tokens")
    }
}

// MARK: - Response

nonisolated struct GrokCitation: Identifiable, Hashable {
    var id: String { url.absoluteString }
    let url: URL
    let title: String?
}

nonisolated struct GrokUsage: Equatable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    /// Of the input, how much SpaceXAI read from its prompt cache (billed at the cached price).
    var cachedTokens: Int = 0
    /// Of the output, how much was reasoning.
    var reasoningTokens: Int = 0
    var webSearches: Int = 0
    var xSearches: Int = 0
    /// Posts and profiles X search read: what it's billed by.
    var xPostsRead: Int = 0
    var xProfilesRead: Int = 0
    /// USD, from SpaceXAI's own accounting (`cost_in_usd_ticks`, 1e10 ticks per dollar), tools included.
    var costUSD: Double?

    nonisolated init(inputTokens: Int = 0, outputTokens: Int = 0, costUSD: Double? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
    }

    nonisolated init?(json: [String: Any]?) {
        guard let json else { return nil }
        func int(_ value: Any?) -> Int { (value as? Int) ?? (value as? Double).map { Int($0) } ?? 0 }
        inputTokens = (json["input_tokens"] as? Int) ?? (json["prompt_tokens"] as? Int) ?? 0
        outputTokens = (json["output_tokens"] as? Int) ?? (json["completion_tokens"] as? Int) ?? 0
        cachedTokens = int((json["input_tokens_details"] as? [String: Any])?["cached_tokens"])
        reasoningTokens = int((json["output_tokens_details"] as? [String: Any])?["reasoning_tokens"])
        if let tools = json["server_side_tool_usage_details"] as? [String: Any] {
            webSearches = int(tools["web_search_calls"])
            xSearches = int(tools["x_search_calls"])
            xPostsRead = int(tools["x_posts_fetched"])
            xProfilesRead = int(tools["x_users_fetched"])
        }
        if let ticks = json["cost_in_usd_ticks"] as? Double {
            costUSD = ticks / 1e10
        } else if let ticks = json["cost_in_usd_ticks"] as? Int {
            costUSD = Double(ticks) / 1e10
        }
    }

    /// What the searches cost, at SpaceXAI's published tool prices.
    var toolCostUSD: Double {
        Double(webSearches) * GrokToolPrices.webSearchCall
            + Double(xPostsRead) * GrokToolPrices.xPostRead
            + Double(xProfilesRead) * GrokToolPrices.xProfileRead
    }
}

nonisolated struct GrokResult {
    var text: String
    var citations: [GrokCitation]
    var usage: GrokUsage?
    var model: String?
    /// Functions Grok asked to run, in order.
    var functionCalls: [GrokFunctionCall] = []
    /// Every output item as SpaceXAI returned it (a JSON array), to send back on the next turn.
    var output: Data? = nil
}

nonisolated enum GrokStreamEvent {
    case textDelta(String)
    /// A server-side tool started ("Searching the web", "Searching X").
    case status(String)
    case citation(GrokCitation)
    case completed(GrokResult)
}

nonisolated enum GrokError: LocalizedError, Equatable {
    case missingKey
    case invalidKey
    case noCredits(String)
    case rateLimited
    case server(Int, String)
    case network(String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: String(localized: "Add your SpaceXAI API key in Settings to use Grok here.")
        case .invalidKey: String(localized: "SpaceXAI didn't accept this API key. Check it in Settings.")
        case .noCredits(let detail):
            String(localized: "SpaceXAI refused the request. Check that your team has credits and that this key may use the model.")
                + (detail.isEmpty ? "" : " (\(detail))")
        case .rateLimited: String(localized: "SpaceXAI is rate limiting this key. Try again in a moment.")
        case let .server(code, message): message.isEmpty ? String(localized: "SpaceXAI returned an error (\(code)).")
            : String(localized: "SpaceXAI error \(code): \(message)")
        case .network(let message): String(localized: "Couldn't reach SpaceXAI: \(message)")
        case .badResponse(let message): String(localized: "Unexpected answer from SpaceXAI: \(message)")
        }
    }
}

// MARK: - Client

nonisolated struct GrokClient {
    nonisolated static let baseURL = URL(string: "https://api.x.ai/v1")!

    let apiKey: String

    nonisolated init(apiKey: String) {
        self.apiKey = apiKey
    }

    nonisolated private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    nonisolated private func request(path: String, method: String = "GET", body: [String: Any]? = nil) throws -> URLRequest {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    /// Models this key can use, with their prices.
    nonisolated func listModels() async throws -> [GrokModelInfo] {
        let (data, response) = try await send(try request(path: "models"))
        try Self.check(response, data: data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else {
            throw GrokError.badResponse("model list")
        }
        return list.compactMap(GrokModelInfo.init(json:))
    }

    /// One complete answer (used for structured tasks like translation batches).
    nonisolated func respond(_ grokRequest: GrokRequest) async throws -> GrokResult {
        #if DEBUG
        if apiKey == Self.simulatedKey { return try await simulatedResponse(grokRequest) }
        #endif
        let (data, response) = try await send(try request(path: "responses", method: "POST", body: grokRequest.body(stream: false)))
        try Self.check(response, data: data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GrokError.badResponse("not JSON")
        }
        if let error = json["error"], !(error is NSNull) {
            throw GrokError.badResponse(Self.message(from: error))
        }
        return Self.result(fromResponse: json)
    }

    /// Streams an answer token by token.
    nonisolated func stream(_ grokRequest: GrokRequest) -> AsyncThrowingStream<GrokStreamEvent, Error> {
        #if DEBUG
        if apiKey == Self.simulatedKey { return simulatedStream(grokRequest) }
        #endif
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var urlRequest = try request(path: "responses", method: "POST", body: grokRequest.body(stream: true))
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let (bytes, response): (URLSession.AsyncBytes, URLResponse)
                    do {
                        (bytes, response) = try await Self.session.bytes(for: urlRequest)
                    } catch {
                        throw GrokError.network(error.localizedDescription)
                    }
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                            if body.count > 64_000 { break }
                        }
                        try Self.check(response, data: body)
                    }

                    var parser = SSEParser()
                    var accumulated = ""
                    var citations: [GrokCitation] = []
                    var finished = false

                    func handle(_ event: SSEEvent) throws {
                        guard event.data != "[DONE]",
                              let data = event.data.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                        for output in try Self.events(from: json, eventName: event.event) {
                            switch output {
                            case .textDelta(let delta):
                                accumulated += delta
                            case .citation(let citation):
                                if !citations.contains(citation) { citations.append(citation) }
                            case .completed(var result):
                                if result.text.isEmpty { result.text = accumulated }
                                for citation in citations where !result.citations.contains(citation) {
                                    result.citations.append(citation)
                                }
                                finished = true
                                continuation.yield(.completed(result))
                                continue
                            case .status:
                                break
                            }
                            continuation.yield(output)
                        }
                    }

                    // Split on "\n" bytes ourselves: `AsyncBytes.lines` also splits on U+2028,
                    // U+2029 and U+0085, which JSON may carry unescaped inside a string.
                    var buffer: [UInt8] = []
                    buffer.reserveCapacity(8192)
                    for try await byte in bytes {
                        if byte == 0x0A {
                            if buffer.last == 0x0D { buffer.removeLast() }
                            let line = String(decoding: buffer, as: UTF8.self)
                            buffer.removeAll(keepingCapacity: true)
                            try Task.checkCancellation()
                            if let event = parser.feed(line) { try handle(event) }
                        } else {
                            buffer.append(byte)
                        }
                    }
                    if !buffer.isEmpty, let event = parser.feed(String(decoding: buffer, as: UTF8.self)) { try handle(event) }
                    if let event = parser.flush() { try handle(event) }
                    if !finished {
                        continuation.yield(.completed(GrokResult(text: accumulated, citations: citations, usage: nil, model: grokRequest.model)))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    nonisolated private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await Self.session.data(for: request)
        } catch {
            throw GrokError.network(error.localizedDescription)
        }
    }

    // MARK: - Parsing (static, unit-tested)

    nonisolated static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200..<300).contains(http.statusCode) else { return }
        let detail: String = {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let error = json["error"] { return message(from: error) }
                if let code = json["code"] as? String { return code }
            }
            return String(data: data.prefix(300), encoding: .utf8) ?? ""
        }()
        switch http.statusCode {
        case 401: throw GrokError.invalidKey
        case 403:
            let lower = detail.lowercased()
            if lower.contains("api key") && (lower.contains("incorrect") || lower.contains("invalid") || lower.contains("disabled") || lower.contains("blocked")) {
                throw GrokError.invalidKey
            }
            // Out of credits, a blocked team, or a key without access to the model.
            throw GrokError.noCredits(detail)
        case 400 where detail.lowercased().contains("api key"):
            throw GrokError.invalidKey
        case 404 where detail.lowercased().contains("model"):
            throw GrokError.server(404, String(localized: "This model isn't available to your key. Pick another one in Settings."))
        case 402: throw GrokError.noCredits(detail)
        case 429: throw GrokError.rateLimited
        default: throw GrokError.server(http.statusCode, detail)
        }
    }

    nonisolated static func message(from error: Any) -> String {
        if let text = error as? String { return text }
        if let dict = error as? [String: Any] {
            return (dict["message"] as? String) ?? (dict["code"] as? String) ?? String(localized: "Unknown error")
        }
        return String(localized: "Unknown error")
    }

    /// Maps one streamed JSON event to zero or more client events.
    nonisolated static func events(from json: [String: Any], eventName: String?) throws -> [GrokStreamEvent] {
        let type = (json["type"] as? String) ?? eventName ?? ""

        if type.hasSuffix("output_text.delta"), let delta = json["delta"] as? String {
            return [.textDelta(delta)]
        }
        if type.hasSuffix("annotation.added"), let annotation = json["annotation"] as? [String: Any],
           let citation = citation(from: annotation) {
            return [.citation(citation)]
        }
        if type == "response.completed" || type == "response.done" {
            let response = (json["response"] as? [String: Any]) ?? json
            return [.completed(result(fromResponse: response))]
        }
        if type == "response.failed" || type == "error" || type == "response.error" {
            let response = json["response"] as? [String: Any]
            let error = response?["error"] ?? json["error"] ?? json["message"] ?? String(localized: "The request failed.")
            throw GrokError.badResponse(message(from: error))
        }
        if type == "response.incomplete" {
            let response = (json["response"] as? [String: Any]) ?? json
            return [.completed(result(fromResponse: response))]
        }
        if let status = searchStatus(type: type, json: json) {
            return [.status(status)]
        }
        if let status = toolStatus(type: type, json: json) {
            return [.status(status)]
        }
        return []
    }

    /// What Grok is searching for, once the query is known: "Searching X for “starship”" when an X
    /// search starts, "Searched the web for “…”" when a web search returns.
    nonisolated static func searchStatus(type: String, json: [String: Any]) -> String? {
        func quoted(_ query: String) -> String? {
            // Leave out X's search operators ("from:SpaceX", "filter:media").
            let words = query.split(separator: " ").filter { !$0.contains(":") }.joined(separator: " ")
            let trimmed = words.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            guard !trimmed.isEmpty else { return nil }
            return "“" + (trimmed.count > 48 ? String(trimmed.prefix(46)) + "…" : trimmed) + "”"
        }
        if type == "response.custom_tool_call_input.done", let input = json["input"] as? String,
           let data = input.data(using: .utf8),
           let arguments = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let query = arguments["query"] as? String, let shown = quoted(query) {
            return "Searching X for \(shown)"
        }
        if type == "response.output_item.done", let item = json["item"] as? [String: Any],
           item["type"] as? String == "web_search_call",
           let action = item["action"] as? [String: Any], let query = action["query"] as? String,
           let shown = quoted(query) {
            return "Searched the web for \(shown)"
        }
        return nil
    }

    nonisolated static func toolStatus(type: String, json: [String: Any]) -> String? {
        if type.contains("reasoning") && type.hasSuffix(".delta") { return "Thinking" }
        var kind = type
        if type.hasSuffix("output_item.added"), let item = json["item"] as? [String: Any], let itemType = item["type"] as? String {
            kind = itemType
            // X search runs as custom tool calls named x_keyword_search, x_semantic_search, …
            if itemType == "custom_tool_call" || itemType == "function_call", let name = item["name"] as? String {
                kind = name
            }
            if itemType == "reasoning" { return "Thinking" }
        } else if !(type.contains("_call") && (type.hasSuffix("in_progress") || type.hasSuffix("searching"))) {
            return nil
        }
        if kind.hasPrefix("x_") || kind.contains("view_x_video") { return "Searching X" }
        if kind.contains("x_search") || kind.contains("x_keyword") || kind.contains("x_semantic") { return "Searching X" }
        if kind.contains("web_search") || kind.contains("browse") { return "Searching the web" }
        if kind.contains("code") { return "Running code" }
        if kind.contains("search") { return "Searching" }
        return nil
    }

    nonisolated static func citation(from annotation: [String: Any]) -> GrokCitation? {
        guard let raw = annotation["url"] as? String, let url = URL(string: raw),
              url.scheme == "https" || url.scheme == "http" else { return nil }
        // SpaceXAI puts the citation's number in `title` ("1", "2"), not the page's title.
        let title = (annotation["title"] as? String).flatMap { $0.isEmpty || $0.allSatisfy(\.isNumber) ? nil : $0 }
        return GrokCitation(url: url, title: title)
    }

    /// Reads the final answer text, citations and usage from a full Responses API object.
    nonisolated static func result(fromResponse json: [String: Any]) -> GrokResult {
        var text = ""
        var citations: [GrokCitation] = []
        for item in json["output"] as? [[String: Any]] ?? [] where (item["type"] as? String) == "message" {
            for content in item["content"] as? [[String: Any]] ?? [] {
                if let piece = content["text"] as? String { text += piece }
                for annotation in content["annotations"] as? [[String: Any]] ?? [] {
                    if let citation = citation(from: annotation), !citations.contains(citation) {
                        citations.append(citation)
                    }
                }
            }
        }
        if text.isEmpty, let outputText = json["output_text"] as? String { text = outputText }
        let outputItems = json["output"] as? [[String: Any]] ?? []
        let calls = outputItems.compactMap { item -> GrokFunctionCall? in
            guard item["type"] as? String == "function_call", let name = item["name"] as? String else { return nil }
            let callID = (item["call_id"] as? String) ?? (item["id"] as? String) ?? UUID().uuidString
            let arguments = (item["arguments"] as? String)
                ?? (item["arguments"].flatMap { try? JSONSerialization.data(withJSONObject: $0) }.map { String(decoding: $0, as: UTF8.self) })
                ?? "{}"
            return GrokFunctionCall(callID: callID, name: name, arguments: arguments)
        }
        let output = outputItems.isEmpty ? nil : try? JSONSerialization.data(withJSONObject: outputItems)
        for raw in json["citations"] as? [Any] ?? [] {
            let urlString = (raw as? String) ?? ((raw as? [String: Any])?["url"] as? String)
            if let urlString, let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true {
                let citation = GrokCitation(url: url, title: nil)
                if !citations.contains(where: { $0.url == url }) { citations.append(citation) }
            }
        }
        return GrokResult(text: text, citations: citations,
                          usage: GrokUsage(json: json["usage"] as? [String: Any]),
                          model: json["model"] as? String, functionCalls: calls, output: output)
    }
}

/// Grok's progress lines, in the user's language. Max Q keeps them in English inside (the list of
/// steps reads them) and translates them for the screen.
nonisolated enum GrokStatusText {
    static func display(_ status: String) -> String {
        let patterns: [(String, (String) -> String)] = [
            ("Searching X for ", { String(localized: "Searching X for \($0)") }),
            ("Searched X for ", { String(localized: "Searched X for \($0)") }),
            ("Searching the web for ", { String(localized: "Searching the web for \($0)") }),
            ("Searched the web for ", { String(localized: "Searched the web for \($0)") }),
        ]
        for (prefix, make) in patterns where status.hasPrefix(prefix) {
            return make(String(status.dropFirst(prefix.count)))
        }
        return switch status {
        case "Thinking": String(localized: "Thinking")
        case "Writing": String(localized: "Writing")
        case "Searching": String(localized: "Searching")
        case "Searching the web": String(localized: "Searching the web")
        case "Searching X": String(localized: "Searching X")
        case "Running code": String(localized: "Running code")
        default: status
        }
    }

    /// A step's verb, for the list of what Grok did ("Searched X").
    static func verb(_ verb: String) -> String {
        switch verb {
        case "Searched X": String(localized: "Searched X")
        case "Searched the web": String(localized: "Searched the web")
        default: verb
        }
    }
}
