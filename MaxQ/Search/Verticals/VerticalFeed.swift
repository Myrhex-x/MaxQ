//
//  VerticalFeed.swift
//  Max Q
//
//  One of the results page's extra tabs (Images, News, Videos): what it has loaded, page by page,
//  and whether more is coming. It loads when its tab is first opened, never before.
//

import Foundation
import Observation

@MainActor
@Observable
final class VerticalFeed<Item: Identifiable & Hashable & Sendable> {
    enum Phase: Equatable {
        case idle, loading, ready, failed(String)
        /// No key for a search API: the tab offers the same search on DuckDuckGo instead.
        case needsKey
    }

    typealias Fetch = @Sendable (_ offset: Int) async throws -> VerticalPage<Item>

    private(set) var phase: Phase = .idle
    private(set) var items: [Item] = []
    private(set) var loadingMore = false
    private(set) var moreFailed = false
    /// When the first page arrived: its items rise into place only then.
    @ObservationIgnored private(set) var arrived = Date.distantPast
    @ObservationIgnored private var next: Int?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var fetch: Fetch
    /// Told when the items change (the news tab groups them into stories).
    @ObservationIgnored var onChange: (() -> Void)?

    var canLoadMore: Bool { next != nil && phase == .ready && !items.isEmpty }

    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    /// Loads the first page, unless it's loaded (or loading) already.
    func load() {
        guard phase == .idle || phase.isFailure else { return }
        start()
    }

    /// Starts over with another request (the filters changed).
    func replace(_ fetch: @escaping Fetch) {
        self.fetch = fetch
        task?.cancel()
        items = []
        next = nil
        loadingMore = false
        moreFailed = false
        onChange?()
        start()
    }

    func reload() {
        task?.cancel()
        start()
    }

    func cancel() {
        task?.cancel()
        task = nil
        if phase == .loading { phase = .idle }
        loadingMore = false
    }

    private func start() {
        phase = .loading
        let fetch = fetch
        task = Task { [weak self] in
            do {
                let page = try await fetch(0)
                guard let self, !Task.isCancelled else { return }
                self.items = page.items
                self.next = page.items.isEmpty ? nil : page.next
                self.arrived = Date()
                self.phase = .ready
                self.onChange?()
            } catch SearchProviderError.needsKey {
                guard let self, !Task.isCancelled else { return }
                self.phase = .needsKey
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    func loadMore() {
        guard let offset = next, !loadingMore, phase == .ready else { return }
        loadingMore = true
        moreFailed = false
        let fetch = fetch
        task = Task { [weak self] in
            let page = try? await fetch(offset)
            guard let self, !Task.isCancelled else { return }
            self.loadingMore = false
            guard let page else { self.moreFailed = true; return }
            let known = Set(self.items.map(\.id))
            let fresh = page.items.filter { !known.contains($0.id) }
            self.items += fresh
            // A page that adds nothing new is the end.
            self.next = fresh.isEmpty ? nil : page.next
            self.onChange?()
        }
    }
}

extension VerticalFeed.Phase {
    var isFailure: Bool {
        switch self {
        case .failed, .needsKey: true
        default: false
        }
    }
}
