//
//  GrokClientTests.swift
//  Max Q
//
//  The fixtures here are small hand-written events in the shapes the SpaceXAI Responses API
//  streams (checked against recorded real streams while building the parser).
//

import Foundation
import Testing
@testable import MaxQ

struct SSEParserTests {
    @Test func parsesDataOnlyEvents() {
        var parser = SSEParser()
        #expect(parser.feed(#"data: {"type":"response.created"}"#) == nil)
        #expect(parser.feed("") == SSEEvent(event: nil, data: #"{"type":"response.created"}"#))
    }

    @Test func keepsEventNamesAndJoinsMultilineData() {
        var parser = SSEParser()
        _ = parser.feed("event: response.output_text.delta")
        _ = parser.feed("data: line one")
        _ = parser.feed("data: line two")
        #expect(parser.feed("") == SSEEvent(event: "response.output_text.delta", data: "line one\nline two"))
    }

    @Test func ignoresCommentsAndHandlesCRLF() {
        var parser = SSEParser()
        #expect(parser.feed(": keep-alive") == nil)
        _ = parser.feed("data: x\r")
        #expect(parser.feed("\r") == SSEEvent(event: nil, data: "x"))
        #expect(parser.flush() == nil)
    }
}

struct GrokStreamEventTests {
    private func events(_ json: String) throws -> [GrokStreamEvent] {
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        return try GrokClient.events(from: object, eventName: nil)
    }

    @Test func textDeltas() throws {
        let out = try events(#"{"type":"response.output_text.delta","item_id":"msg_1","output_index":1,"content_index":0,"delta":"Hel"}"#)
        guard case .textDelta(let text) = out.first else { Issue.record("expected a delta"); return }
        #expect(text == "Hel")
    }

    @Test func reasoningIsShownAsThinkingNotAsAnswerText() throws {
        let out = try events(#"{"type":"response.reasoning_summary_text.delta","delta":"Let me think"}"#)
        guard case .status(let status) = out.first else { Issue.record("expected a status"); return }
        #expect(status == "Thinking")
    }

    @Test func toolProgress() throws {
        let web = try events(#"{"type":"response.output_item.added","item":{"type":"web_search_call","id":"ws_1","status":"in_progress"}}"#)
        guard case .status(let webStatus) = web.first else { Issue.record("expected web status"); return }
        #expect(webStatus == "Searching the web")

        let x = try events(#"{"type":"response.output_item.added","item":{"type":"custom_tool_call","call_id":"xs_1","name":"x_keyword_search","input":""}}"#)
        guard case .status(let xStatus) = x.first else { Issue.record("expected X status"); return }
        #expect(xStatus == "Searching X")

        let searching = try events(#"{"type":"response.web_search_call.searching","item_id":"ws_1","output_index":0}"#)
        guard case .status = searching.first else { Issue.record("expected searching status"); return }

        #expect(try events(#"{"type":"response.content_part.added"}"#).isEmpty)
    }

    @Test func citations() throws {
        let out = try events(#"{"type":"response.output_text.annotation.added","annotation":{"type":"url_citation","url":"https://x.com/i/status/1","start_index":3,"end_index":9,"title":"1"}}"#)
        guard case .citation(let citation) = out.first else { Issue.record("expected a citation"); return }
        #expect(citation.url.absoluteString == "https://x.com/i/status/1")

        // Only web links count as sources.
        #expect(try events(#"{"type":"response.output_text.annotation.added","annotation":{"type":"url_citation","url":"javascript:alert(1)"}}"#).isEmpty)
    }

    @Test func completedCarriesUsageAndCost() throws {
        let out = try events("""
        {"type":"response.completed","response":{"id":"r1","model":"grok-4.3","status":"completed",
         "output":[{"type":"reasoning","encrypted_content":"…"},
                   {"type":"message","content":[{"type":"output_text","text":"Max Q is ",
                     "annotations":[{"type":"url_citation","url":"https://example.com/a"}]},
                    {"type":"output_text","text":"a browser."}]}],
         "usage":{"input_tokens":1200,"output_tokens":340,"cost_in_usd_ticks":21500000}}}
        """)
        guard case .completed(let result) = out.first else { Issue.record("expected completion"); return }
        #expect(result.text == "Max Q is a browser.")
        #expect(result.model == "grok-4.3")
        #expect(result.citations.map(\.url.absoluteString) == ["https://example.com/a"])
        #expect(result.usage?.inputTokens == 1200)
        #expect(result.usage?.outputTokens == 340)
        #expect(abs((result.usage?.costUSD ?? 0) - 0.00215) < 1e-12)
    }

    @Test func failuresThrowWithTheServerMessage() {
        #expect(throws: GrokError.badResponse("Model overloaded")) {
            _ = try events(#"{"type":"response.failed","response":{"error":{"code":"server_error","message":"Model overloaded"}}}"#)
        }
        #expect(throws: GrokError.badResponse("bad things")) {
            _ = try events(#"{"type":"error","code":"x","message":"bad things"}"#)
        }
    }
}

struct GrokHTTPErrorTests {
    private func check(_ status: Int, _ body: String) -> GrokError? {
        let response = HTTPURLResponse(url: URL(string: "https://api.x.ai/v1/responses")!, statusCode: status, httpVersion: nil, headerFields: nil)!
        do {
            try GrokClient.check(response, data: Data(body.utf8))
            return nil
        } catch {
            return error as? GrokError
        }
    }

    @Test func mapsStatusCodes() {
        #expect(check(200, "{}") == nil)
        #expect(check(400, #"{"code":"Client specified an invalid argument","error":"Incorrect API key provided: xa***kA."}"#) == .invalidKey)
        #expect(check(401, "") == .invalidKey)
        #expect(check(429, "") == .rateLimited)
        if case .noCredits = check(403, #"{"code":"The caller does not have permission to execute the specified operation","error":"Your team has no credits"}"#) {} else {
            Issue.record("403 should explain credits / access")
        }
        if case .server(404, _) = check(404, #"{"code":"not-found","error":"The model grok-9 does not exist or your team does not have access to it."}"#) {} else {
            Issue.record("404 for a model should be a server error with guidance")
        }
    }
}

struct GrokRequestTests {
    @Test func bodyIsPrivateAndCarriesTools() throws {
        let request = GrokRequest(
            model: "grok-4.3",
            instructions: "Be brief.",
            input: [GrokMessage(role: .user, content: "Hi"), GrokMessage(role: .assistant, content: "Hello")],
            tools: [.webSearch(allowedDomains: ["grokipedia.com"]), .xSearch(allowedHandles: ["SpaceX"])],
            maxTurns: 4
        )
        let body = request.body(stream: true)
        #expect(body["store"] as? Bool == false)
        #expect(body["stream"] as? Bool == true)
        #expect(body["max_turns"] as? Int == 4)
        #expect(body["max_tool_calls"] == nil)
        let input = try #require(body["input"] as? [[String: String]])
        #expect(input == [["role": "user", "content": "Hi"], ["role": "assistant", "content": "Hello"]])
        let tools = try #require(body["tools"] as? [[String: Any]])
        #expect(tools[0]["type"] as? String == "web_search")
        #expect((tools[0]["filters"] as? [String: [String]])?["allowed_domains"] == ["grokipedia.com"])
        #expect(tools[1]["type"] as? String == "x_search")
        #expect(tools[1]["allowed_x_handles"] as? [String] == ["SpaceX"])
        // The body must be valid JSON.
        _ = try JSONSerialization.data(withJSONObject: body)
    }

    @Test func domainFiltersAreCappedAndExclusive() {
        let many = GrokTool.webSearch(allowedDomains: ["a.com", "b.com", "c.com", "d.com", "e.com", "f.com"], excludedDomains: ["z.com"]).json
        let filters = many["filters"] as? [String: [String]]
        #expect(filters?["allowed_domains"]?.count == 5)
        #expect(filters?["excluded_domains"] == nil)
    }

    @Test func modelPricesAreConverted() throws {
        let info = try #require(GrokModelInfo(json: ["id": "grok-4.3", "prompt_text_token_price": 12500, "completion_text_token_price": 25000]))
        #expect(info.inputPerMillion == 1.25)
        #expect(info.outputPerMillion == 2.5)
        #expect(info.priceLabel == "$1.25 in · $2.50 out per 1M tokens")
    }

    @Test func picksTheBestAvailableModel() {
        #expect(GrokAccount.pick(from: GrokAccount.preferredModels, available: ["grok-4.7", "grok-4.3", "grok-imagine-image-2.0"]) == "grok-4.3")
        #expect(GrokAccount.pick(from: GrokAccount.preferredModels, available: ["grok-imagine-image", "grok-5"]) == "grok-5")
        #expect(GrokAccount.pick(from: GrokAccount.preferredModels, available: []) == nil)
    }
}

@Suite(.serialized)
struct GrokKeyStoreTests {
    @Test func savesReadsReplacesAndDeletesOnlyItsOwnItem() {
        let original = GrokKeyStore.service
        GrokKeyStore.service = "com.myrhex.MaxQ.tests.\(UUID().uuidString)"
        defer {
            GrokKeyStore.delete()
            GrokKeyStore.service = original
        }
        #expect(GrokKeyStore.read() == nil)
        #expect(GrokKeyStore.save("  xai-test-one  "))
        #expect(GrokKeyStore.read() == "xai-test-one")
        #expect(GrokKeyStore.save("xai-test-two"))
        #expect(GrokKeyStore.read() == "xai-test-two")
        #expect(!GrokKeyStore.save("   "))
        GrokKeyStore.delete()
        #expect(GrokKeyStore.read() == nil)
        #expect(GrokKeyStore.service != GrokKeyStore.productionService)
    }
}
