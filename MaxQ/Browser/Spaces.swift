//
//  Spaces.swift
//  Max Q
//
//  Spaces: Personal and Work (or any others), each with its own sign-ins, cookies and site data,
//  and its own tabs. A window shows one space at a time; switching saves the window's tabs to the
//  space it leaves and brings back the other's. Each space's website data lives in a store of its
//  own (WebKit keeps them apart), so being signed in to X at work doesn't sign Personal in.
//  History, bookmarks and Max Q's settings are shared.
//

import Foundation
import Observation
import WebKit

nonisolated struct BrowserSpace: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    /// One character shown for the space (its initial, or an emoji the user chose).
    var mark: String

    init(name: String) {
        id = UUID()
        self.name = name
        mark = String(name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "S")
    }
}

@MainActor
@Observable
final class SpaceStore {
    static let shared = SpaceStore()

    /// The spaces besides Personal (the default, which has no id).
    private(set) var spaces: [BrowserSpace] = []
    /// The space the last window was in, opened again next launch.
    private(set) var lastUsed: UUID?
    @ObservationIgnored private var stores: [UUID: WKWebsiteDataStore] = [:]

    private static let fileName = "Spaces.json"

    private struct Saved: Codable {
        var spaces: [BrowserSpace]
        var lastUsed: UUID?
    }

    private init() {
        let saved = Storage.load(Saved.self, from: Self.fileName)
        spaces = saved?.spaces ?? []
        lastUsed = saved?.lastUsed.flatMap { id in spaces.contains { $0.id == id } ? id : nil }
    }

    /// The website data of a space (Personal's when `id` is nil).
    func dataStore(for id: UUID?) -> WKWebsiteDataStore {
        guard let id else { return .default() }
        if let store = stores[id] { return store }
        let store = WKWebsiteDataStore(forIdentifier: id)
        stores[id] = store
        return store
    }

    func space(_ id: UUID?) -> BrowserSpace? {
        id.flatMap { id in spaces.first { $0.id == id } }
    }

    func name(of id: UUID?) -> String {
        space(id)?.name ?? String(localized: "Personal")
    }

    @discardableResult
    func create(_ name: String) -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let space = BrowserSpace(name: trimmed.isEmpty ? String(localized: "New space") : String(trimmed.prefix(24)))
        spaces.append(space)
        save()
        return space.id
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        spaces[index].name = String(trimmed.prefix(24))
        spaces[index].mark = String(trimmed.first.map { String($0).uppercased() } ?? "S")
        save()
    }

    /// Removes a space and everything sites kept in it (its sign-ins, cookies and data). Windows
    /// in it must have left it first.
    func delete(_ id: UUID) async {
        spaces.removeAll { $0.id == id }
        if lastUsed == id { lastUsed = nil }
        stores[id] = nil
        SessionStore.clear(space: id)
        save()
        try? await WKWebsiteDataStore.remove(forIdentifier: id)
    }

    func noteUsed(_ id: UUID?) {
        guard lastUsed != id else { return }
        lastUsed = id
        save()
    }

    /// Every space's website data, for "Clear cookies and website data".
    func clearAllWebsiteData() async {
        for space in spaces {
            let store = dataStore(for: space.id)
            let types = WKWebsiteDataStore.allWebsiteDataTypes()
            await store.removeData(ofTypes: types, modifiedSince: .distantPast)
        }
    }

    private func save() {
        let snapshot = Saved(spaces: spaces, lastUsed: lastUsed)
        Storage.save(snapshot, to: Self.fileName)
    }
}
