//
//  CostTests.swift
//  Max Q
//

import Foundation
import Testing
@testable import MaxQ

struct CostTests {
    @Test func effortsAskForReasoningOnlyWhereModelsTakeIt() {
        #expect(GrokEffort.fast.reasoningEffort(for: "grok-4.3", supported: nil) == "none")
        #expect(GrokEffort.auto.reasoningEffort(for: "grok-4.3", supported: nil) == "low")
        #expect(GrokEffort.expert.reasoningEffort(for: "grok-4.7", supported: nil) == "medium")
        #expect(GrokEffort.expert.reasoningEffort(for: "grok-4.3", supported: nil) == "high")
        // Grok 4.7 can't skip reasoning: Fast asks for the least it takes.
        #expect(GrokEffort.fast.reasoningEffort(for: "grok-4.7", supported: nil) == "low")
        // A model that takes no effort gets none sent.
        #expect(GrokEffort.auto.reasoningEffort(for: "grok-4.20-0309-non-reasoning", supported: nil) == nil)
        // The live model list wins over what Max Q knows.
        #expect(GrokEffort.fast.reasoningEffort(for: "grok-4.3", supported: ["low", "high"]) == "low")
    }

    @Test func requestsCarryReasoningAndTheCacheKey() {
        var request = GrokRequest(model: "grok-4.3", input: [GrokMessage(role: .user, content: "hi")])
        #expect(request.body(stream: true)["reasoning"] == nil)
        request.reasoningEffort = "none"
        request.promptCacheKey = "abc"
        let body = request.body(stream: true)
        #expect((body["reasoning"] as? [String: String])?["effort"] == "none")
        #expect(body["prompt_cache_key"] as? String == "abc")
    }

    @Test func readsWhatAnAnswerUsed() {
        let usage = GrokUsage(json: [
            "input_tokens": 6120, "output_tokens": 240,
            "input_tokens_details": ["cached_tokens": 2048],
            "output_tokens_details": ["reasoning_tokens": 180],
            "server_side_tool_usage_details": ["web_search_calls": 2, "x_search_calls": 1, "x_posts_fetched": 19, "x_users_fetched": 1],
            "cost_in_usd_ticks": 1_134_000_000,
        ])
        #expect(usage?.cachedTokens == 2048)
        #expect(usage?.reasoningTokens == 180)
        #expect(usage?.webSearches == 2)
        #expect(usage?.xPostsRead == 19)
        #expect(usage?.xProfilesRead == 1)
        #expect(abs((usage?.costUSD ?? 0) - 0.1134) < 0.0000001)
        #expect(abs((usage?.toolCostUSD ?? 0) - (0.01 + 0.095 + 0.01)) < 0.0000001)
        // Numbers follow the Mac's own format ("6,120" or "6 120").
        let expected = "Grok 4.3 · \(6120.formatted()) tokens read, \(2048.formatted()) of them cached"
        #expect(UsageLine.text(usage: usage, model: "grok-4.3")?.hasPrefix(expected) == true)
    }

    @Test func readsModelCapabilities() {
        let info = GrokModelInfo(json: [
            "id": "grok-4.3", "prompt_text_token_price": 12500, "completion_text_token_price": 25000,
            "cached_prompt_text_token_price": 2000,
            "capabilities": ["reasoning_effort": ["none", "low", "medium"], "default_reasoning_effort": "low"],
        ])
        #expect(info?.inputPerMillion == 1.25)
        #expect(info?.cachedInputPerMillion == 0.2)
        #expect(info?.reasoningEfforts == ["none", "low", "medium"])
        #expect(info?.defaultReasoningEffort == "low")
    }

    @Test func searchesXOnlyForNews() {
        #expect(NewsDetector.isNews("starship launch news"))
        #expect(NewsDetector.isNews("what happened to the grok outage"))
        #expect(NewsDetector.isNews("@SpaceX"))
        #expect(NewsDetector.isNews("reactions to the keynote"))
        #expect(NewsDetector.isNews("what are people saying about the election"))
        #expect(!NewsDetector.isNews("where does elon musk live"))
        #expect(!NewsDetector.isNews("how to calm down"))
        #expect(!NewsDetector.isNews("c# tutorial"))
        #expect(!NewsDetector.isNews("a book on xenon"))
        #expect(!NewsDetector.isNews("chocolate cake recipe"))
        #expect(XSearchPolicy.off.allows("starship news") == false)
        #expect(XSearchPolicy.always.allows("chocolate cake recipe"))
    }

    @Test func saysMoneyThePlainWay() {
        #expect(GrokAccount.friendlyCost(0.002) == "<1¢")
        #expect(GrokAccount.friendlyCost(0.002, approximate: true) == "under 1¢")
        #expect(GrokAccount.friendlyCost(0.0134) == "1¢")
        #expect(GrokAccount.friendlyCost(0.1134, approximate: true) == "about 11¢")
        #expect(GrokAccount.friendlyCost(1.2) == "$1.20")
        #expect(UsageLine.modelName("grok-4.20-0309-non-reasoning") == "Grok 4.20 0309 non reasoning")
        #expect(UsageLine.modelName("grok-4.7") == "Grok 4.7")
    }
}
