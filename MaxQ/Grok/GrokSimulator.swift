//
//  GrokSimulator.swift
//  Max Q
//
//  Debug builds only: a pretend Grok, so the answer screens can be checked without a key and
//  without spending anything. It turns on only with the launch argument `-MaxQSimulatedGrok YES`,
//  and it never touches the network. Each feature gets an answer in its own shape (a check's
//  verdict, research notes, an agent's next action), all saying they're simulated.
//

#if DEBUG
import Foundation

extension GrokClient {
    nonisolated static let simulatedKey = "maxq-simulated"

    /// Launched with `-MaxQSimulatedGrok YES`.
    nonisolated static var simulationEnabled: Bool {
        UserDefaults.standard.bool(forKey: "MaxQSimulatedGrok")
    }

    nonisolated func simulatedStream(_ request: GrokRequest) -> AsyncThrowingStream<GrokStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let question = request.input.last?.content.components(separatedBy: "\n").first ?? "this"
                let searchesX = request.tools.contains { if case .xSearch = $0 { true } else { false } }
                func pause(_ ms: Int) async throws { try await Task.sleep(for: .milliseconds(ms)) }
                do {
                    if !request.tools.isEmpty {
                        try await pause(350)
                        continuation.yield(.status("Searching the web"))
                        try await pause(700)
                        continuation.yield(.status("Searched the web for “\(question.prefix(40))”"))
                        if searchesX {
                            try await pause(500)
                            continuation.yield(.status("Searching X for “\(question.prefix(40))”"))
                        }
                    }
                    try await pause(400)
                    for source in ["https://reference.example/simulation", "https://gazette.example/streaming", "https://journal.example/citations"] {
                        if let url = URL(string: source) { continuation.yield(.citation(GrokCitation(url: url, title: nil))) }
                    }
                    let answer = Self.simulatedText(for: request, question: question)
                    var index = answer.startIndex
                    while index < answer.endIndex {
                        try Task.checkCancellation()
                        let end = answer.index(index, offsetBy: 6, limitedBy: answer.endIndex) ?? answer.endIndex
                        continuation.yield(.textDelta(String(answer[index..<end])))
                        index = end
                        try await pause(request.purpose == .research ? 8 : 18)
                    }
                    var usage = GrokUsage(inputTokens: 6_120, outputTokens: 240, costUSD: searchesX ? 0.1134 : 0.0134)
                    usage.webSearches = request.tools.isEmpty ? 0 : 1
                    usage.xSearches = searchesX ? 1 : 0
                    usage.xPostsRead = searchesX ? 19 : 0
                    usage.reasoningTokens = request.reasoningEffort == "none" ? 0 : 180
                    continuation.yield(.completed(GrokResult(text: answer, citations: [], usage: usage, model: request.model)))
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// A whole answer at once: structured answers (a research plan) and an agent's next step.
    nonisolated func simulatedResponse(_ request: GrokRequest) async throws -> GrokResult {
        try await Task.sleep(for: .milliseconds(700))
        let usage = GrokUsage(inputTokens: 4_200, outputTokens: 160, costUSD: 0.0061)
        if request.purpose == .agent {
            // Read the page, scroll once, then finish: an agent run that changes nothing. A task
            // that says "click" clicks the page's first link instead of scrolling, and one that says
            // "wikipedia" then opens wikipedia.org (which the page doesn't link to, so Max Q asks).
            let items = request.items.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
            let outputs = items.filter { $0["type"] as? String == "function_call_output" }.compactMap { $0["output"] as? String }
            let turn = outputs.count
            let task = request.input.first?.content.lowercased() ?? ""
            let firstLink = outputs.last?.components(separatedBy: "\n").lazy
                .compactMap { line -> Int? in
                    guard line.hasPrefix("["), line.contains("] link") else { return nil }
                    return Int(line.dropFirst().prefix { $0.isNumber })
                }.first
            if let script = Self.agentScript(task), turn > 0 {
                // "harness: [[\"type\", \"Search\", \"text\", true], [\"click\", \"Delete\"], …]": the
                // calls in order after reading the page, each control found by its label.
                let step = turn - 1 < script.count ? script[turn - 1] : ["finish"]
                let name = step.first as? String ?? "finish"
                let view = outputs.last { $0.contains("Controls:") } ?? ""
                let ref = (step.count > 1 ? step[1] as? String : nil).flatMap { Self.agentRef(labelled: $0, in: view) }
                var arguments: [String: Any] = [:]
                switch name {
                case "type":
                    arguments = ["ref": ref ?? 0, "text": step.count > 2 ? step[2] : "", "submit": step.count > 3 ? step[3] : false]
                case "click": arguments = ["ref": ref ?? 0]
                case "select": arguments = ["ref": ref ?? 0, "option": step.count > 2 ? step[2] : ""]
                case "navigate": arguments = ["url": step.count > 1 ? step[1] : ""]
                case "scroll": arguments = ["direction": "down"]
                case "ask_user": arguments = ["question": step.count > 1 ? step[1] : "Which one?"]
                default: arguments = ["summary": "Simulated harness run finished."]
                }
                let json = String(data: (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data(), encoding: .utf8) ?? "{}"
                let call = GrokFunctionCall(callID: "sim-\(turn)", name: name, arguments: json)
                let item: [String: Any] = ["type": "function_call", "call_id": call.callID, "name": call.name, "arguments": call.arguments]
                let output = try? JSONSerialization.data(withJSONObject: [item])
                return GrokResult(text: "", citations: [], usage: usage, model: request.model, functionCalls: [call], output: output)
            }
            let call: GrokFunctionCall = switch turn {
            case 0: GrokFunctionCall(callID: "sim-0", name: "read_page", arguments: "{}")
            case 1 where task.contains("click") && firstLink != nil:
                GrokFunctionCall(callID: "sim-1", name: "click", arguments: #"{"ref":\#(firstLink ?? 1)}"#)
            case 1: GrokFunctionCall(callID: "sim-1", name: "scroll", arguments: #"{"direction":"down"}"#)
            case 2 where task.contains("wikipedia"):
                GrokFunctionCall(callID: "sim-2", name: "navigate", arguments: #"{"url":"https://www.wikipedia.org/"}"#)
            default: GrokFunctionCall(callID: "sim-\(turn)", name: "finish",
                                      arguments: #"{"summary":"Simulated agent: a real run does what the task asks, step by step. This one only read the page and moved around."}"#)
            }
            let item: [String: Any] = ["type": "function_call", "call_id": call.callID, "name": call.name, "arguments": call.arguments]
            let output = try? JSONSerialization.data(withJSONObject: [item])
            return GrokResult(text: "", citations: [], usage: usage, model: request.model, functionCalls: [call], output: output)
        }
        if let schema = request.jsonSchema {
            let json: String = switch schema.name {
            case "research_plan":
                #"{"title":"A simulated research plan","questions":["What is it, in plain terms?","What happened most recently?","What do the main sources disagree about?","What comes next?"]}"#
            default:
                #"{"items":[]}"#
            }
            return GrokResult(text: json, citations: [], usage: usage, model: request.model)
        }
        let question = request.input.last?.content.components(separatedBy: "\n").first ?? "this"
        return GrokResult(text: Self.simulatedText(for: request, question: question), citations: [], usage: usage, model: request.model)
    }

    /// The calls a "harness:" task lists, as JSON arrays, or the launch argument `-MaxQAgentHarness`
    /// lists (so the task itself can read like a person's). Quote that JSON for the shell and for
    /// macOS, which drops an argument starting with "[": `-MaxQAgentHarness '"[[\"click\",\"Delete\"]]"'`.
    nonisolated private static func agentScript(_ task: String) -> [[Any]]? {
        let json: String
        if let range = task.range(of: "harness:") {
            json = task[range.upperBound...].components(separatedBy: "\n\n").first ?? ""
        } else if let given = UserDefaults.standard.string(forKey: "MaxQAgentHarness") {
            json = given
        } else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [[Any]]
    }

    /// The number of the control whose label contains `label`, in a view of the page.
    nonisolated private static func agentRef(labelled label: String, in view: String) -> Int? {
        for line in view.components(separatedBy: "\n") where line.hasPrefix("[") {
            guard let quote = line.firstIndex(of: "\""), line[quote...].lowercased().contains(label.lowercased()) else { continue }
            return Int(line.dropFirst().prefix { $0.isNumber })
        }
        return nil
    }

    nonisolated private static func simulatedText(for request: GrokRequest, question: String) -> String {
        switch request.purpose {
        case .check:
            return """
            Verdict: Unverified
            Summary: This is a simulated check: debug builds show this instead of asking SpaceXAI, so nothing is spent.
            + A real check lists what supports the claim, with its sources [[1]](https://reference.example/simulation).
            - And what contradicts it, also sourced [[2]](https://gazette.example/streaming).
            ~ Context that changes how the claim reads comes last [[3]](https://journal.example/citations).
            """
        case .research:
            if request.tools.isEmpty {
                return """
                # A simulated report

                This report is simulated: debug builds write it instead of asking SpaceXAI [[1]](https://reference.example/simulation).

                ## What it is
                A real report starts with the plain answer, then goes deeper section by section [[2]](https://gazette.example/streaming).

                ## What happened recently
                - Each finding carries the sources it came from [[3]](https://journal.example/citations).
                - Disagreements between sources are named, not smoothed over.

                ## What to watch
                The last section says what's still open.
                """
            }
            return "Simulated notes on “\(question.prefix(60))”: a real step would list what the sources say, with citations [[1]](https://reference.example/simulation)."
        case .article:
            return "This is a simulated answer about the article. A real one quotes the section it comes from, like [Concept and History](maxq-section://h-concept-and-history), so a click takes you there."
        case .video:
            return "This is a simulated answer about the video. A real one points at moments like [00:42](maxq-seek://42) and [03:10](maxq-seek://190), which jump the video there."
        default:
            // Only the results page asks for follow-up questions.
            return simulatedAnswer(for: question, followUps: request.purpose == .answer)
        }
    }

    nonisolated private static func simulatedAnswer(for question: String, followUps: Bool) -> String {
        let answer = """
        **\(question.prefix(60))** is a simulated answer: debug builds launched with the simulator show this \
        text instead of asking SpaceXAI, so nothing is spent [[1]](https://reference.example/simulation).

        - The answer streams in a few letters at a time, the way Grok's does [[2]](https://gazette.example/streaming).
        - Citations become the sources' names [[3]](https://journal.example/citations).
        - The cost line shows what a real answer of this size costs.

        Nothing here comes from the web.
        """
        guard followUps else { return answer }
        return answer + """

        ---follow-ups---
        How would a real answer about \(question.prefix(40)) differ?
        What does an answer cost at each effort?
        Which sources does Grok usually cite?
        """
    }
}
#endif
