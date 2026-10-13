//
//  GrokipediaPanelModel.swift
//  Max Q
//
//  Per-window state for the native Grokipedia card beside search results: which query it's for,
//  whether it's loading, the card, and whether the user closed it. Fetching only happens for a
//  search the user ran, and in private windows only when they ask for it.
//

import Foundation
import Observation

@MainActor
@Observable
final class GrokipediaPanelModel {
    enum State: Equatable {
        case idle
        case loading(String)
        case ready(GrokipediaCard)
        /// Grokipedia has no article for this query.
        case none(String)
    }

    private(set) var state: State = .idle
    /// Queries whose card the user closed in this window.
    private(set) var dismissed: Set<String> = []
    /// Queries the user asked for explicitly (when the card isn't automatic).
    private(set) var requested: Set<String> = []

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var currentQuery: String?

    /// Called whenever the selected tab's search query changes.
    func update(query: String?, automatic: Bool) {
        guard let query, !query.isEmpty else {
            task?.cancel()
            currentQuery = nil
            state = .idle
            return
        }
        guard query != currentQuery || state == .idle else { return }
        currentQuery = query
        guard !dismissed.contains(query) else { state = .idle; return }
        if automatic || requested.contains(query) {
            load(query)
        } else {
            state = .idle
        }
    }

    func request(_ query: String) {
        requested.insert(query)
        dismissed.remove(query)
        currentQuery = query
        load(query)
    }

    func dismiss(_ query: String) {
        dismissed.insert(query)
        task?.cancel()
        state = .idle
    }

    func isDismissed(_ query: String) -> Bool { dismissed.contains(query) }

    private func load(_ query: String) {
        task?.cancel()
        state = .loading(query)
        task = Task { [weak self] in
            let card = await GrokipediaService.card(for: query)
            guard !Task.isCancelled, let self, self.currentQuery == query else { return }
            self.state = card.map(State.ready) ?? .none(query)
        }
    }
}
