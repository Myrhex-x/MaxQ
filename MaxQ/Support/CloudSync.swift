//
//  CloudSync.swift
//  Max Q
//
//  iCloud sync for what the user keeps: Collections, followed searches and bookmarks, between
//  their Macs, in their own iCloud account (CloudKit's private database, in encrypted fields, so
//  with Advanced Data Protection only their devices can read it). Tabs, history, Spaces' sign-ins,
//  pages read and the API key never leave the Mac.
//
//  Each kind is one record holding every item by id, with when it last changed, and what was
//  removed. Two Macs merge item by item: the latest change wins, and a removal wins over older
//  changes. It syncs when turned on, at launch, every fifteen minutes while Max Q is open, and a
//  few seconds after something changes.
//
//  It stays off until Max Q is built with an iCloud container: without the entitlement CloudKit
//  isn't touched at all, and Settings says sync isn't set up in this copy.
//

import Foundation
import Observation
import Security
#if canImport(CloudKit)
import CloudKit
#endif

/// A store whose contents sync through iCloud.
@MainActor
protocol SyncedStore: AnyObject {
    /// The record's name in iCloud ("collections").
    static var syncName: String { get }
    /// What syncs, by a stable id, each item encoded.
    func syncItems() -> [String: Data]
    /// Replaces what syncs with `items`, merged from every Mac.
    func applySynced(_ items: [String: Data])
    /// An item as this Mac would encode it (nil when it can't read it, say from a newer Max Q).
    func normalized(_ data: Data) -> Data?
}

/// Every item of one store, with when it changed, and what was removed (and when).
nonisolated struct SyncDocument: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        var data: Data
        var modified: Date
    }

    var entries: [String: Entry] = [:]
    var removed: [String: Date] = [:]

    /// Item by item: the latest change wins; a removal wins over changes made before it.
    static func merge(_ a: SyncDocument, _ b: SyncDocument, now: Date = Date()) -> SyncDocument {
        var result = SyncDocument()
        let ids = Set(a.entries.keys).union(b.entries.keys).union(a.removed.keys).union(b.removed.keys)
        for id in ids {
            let entry = [a.entries[id], b.entries[id]].compactMap { $0 }.max { $0.modified < $1.modified }
            let removed = [a.removed[id], b.removed[id]].compactMap { $0 }.max()
            if let entry, removed.map({ $0 < entry.modified }) ?? true {
                result.entries[id] = entry
            } else if let removed {
                result.removed[id] = removed
            }
        }
        // Removals are remembered for three months, long enough for a Mac that was away.
        result.removed = result.removed.filter { now.timeIntervalSince($0.value) < 90 * 86_400 }
        return result
    }

    /// `items` as they are now, against what was last known: what's new or different changed now,
    /// what's gone was removed now. `normalize` is how this Mac encodes a known item: one that only
    /// reads differently here (a field this version doesn't know) hasn't changed, and one this Mac
    /// can't read at all isn't removed by not being here.
    func updated(with items: [String: Data], now: Date = Date(), normalize: (Data) -> Data? = { $0 }) -> SyncDocument {
        var document = self
        for (id, data) in items {
            if let entry = document.entries[id], entry.data == data || normalize(entry.data) == data { continue }
            document.entries[id] = Entry(data: data, modified: now)
            document.removed[id] = nil
        }
        for (id, entry) in document.entries where items[id] == nil && normalize(entry.data) != nil {
            document.entries[id] = nil
            document.removed[id] = now
        }
        return document
    }
}

/// Stable encoding for synced items: the same item always gives the same bytes.
nonisolated enum SyncCoding {
    static func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return (try? encoder.encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) -> T? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(type, from: data)
    }
}

@MainActor
@Observable
final class CloudSync {
    static let shared = CloudSync()

    enum Status: Equatable {
        /// This copy of Max Q has no iCloud container.
        case unavailable
        case off
        case noAccount
        case syncing
        case synced(Date)
        case failed(String)
    }

    private(set) var status: Status

    @ObservationIgnored private var stores: [String: any SyncedStore] = [:]
    @ObservationIgnored private var known: [String: SyncDocument] = [:]
    @ObservationIgnored private var applying = false
    @ObservationIgnored private var changed: Set<String> = []
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var zoneReady = false

    private static let fileName = "CloudSync.json"
    private static let zoneName = "MaxQ"
    private static let recordType = "SyncedStore"
    /// CloudKit records hold up to 1 MB; the payload stays under it.
    private static let maxPayload = 900_000

    private struct Saved: Codable {
        var known: [String: SyncDocument]
        var lastSynced: Date?
    }

    /// The iCloud container this copy is signed for, if any.
    nonisolated static let containerIdentifier: String? = {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        let services = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil) as? [String]
        guard services?.contains("CloudKit") == true else { return nil }
        let containers = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil) as? [String]
        return containers?.first
    }()

    var isAvailable: Bool { Self.containerIdentifier != nil }

    private init() {
        let saved = Storage.load(Saved.self, from: Self.fileName)
        known = saved?.known ?? [:]
        if Self.containerIdentifier == nil {
            status = .unavailable
        } else if !AppSettings.shared.iCloudSync {
            status = .off
        } else {
            status = saved?.lastSynced.map { .synced($0) } ?? .off
        }
    }

    // MARK: - Turning it on

    /// Registers the synced stores and, when sync is on, syncs now and every fifteen minutes.
    func start() {
        guard isAvailable else { return }
        if stores.isEmpty {
            let all: [any SyncedStore] = [CollectionStore.shared, FollowStore.shared, BookmarkStore.shared]
            for store in all { stores[type(of: store).syncName] = store }
        }
        guard AppSettings.shared.iCloudSync else { return }
        syncAll()
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncAll() }
            }
        }
    }

    func setEnabled(_ on: Bool) {
        guard isAvailable else { return }
        AppSettings.shared.iCloudSync = on
        if on {
            start()
        } else {
            timer?.invalidate()
            timer = nil
            running?.cancel()
            pushTask?.cancel()
            status = .off
        }
    }

    /// A store changed on this Mac: it syncs a few seconds later (several changes go together).
    func noteChange(_ name: String) {
        guard !applying, isAvailable, AppSettings.shared.iCloudSync else { return }
        changed.insert(name)
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            let names = self.changed
            self.changed = []
            self.sync(names)
        }
    }

    func syncAll() {
        sync(Set(stores.keys))
    }

    // MARK: - Syncing

    private func sync(_ names: Set<String>) {
        guard isAvailable, AppSettings.shared.iCloudSync, !names.isEmpty else { return }
        #if canImport(CloudKit)
        let previous = running
        running = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            status = .syncing
            do {
                let container = CKContainer(identifier: Self.containerIdentifier ?? "")
                guard try await container.accountStatus() == .available else {
                    status = .noAccount
                    return
                }
                let database = container.privateCloudDatabase
                let zone = CKRecordZone(zoneName: Self.zoneName)
                if !zoneReady {
                    _ = try await database.modifyRecordZones(saving: [zone], deleting: [])
                    zoneReady = true
                }
                for name in names.sorted() {
                    try await sync(name, in: database, zone: zone.zoneID)
                }
                let now = Date()
                status = .synced(now)
                persist(lastSynced: now)
            } catch {
                guard !Task.isCancelled else { return }
                status = .failed(Self.message(for: error))
            }
        }
        #endif
    }

    #if canImport(CloudKit)
    /// One store: what changed here, merged with iCloud's copy, applied here and saved there.
    private func sync(_ name: String, in database: CKDatabase, zone: CKRecordZone.ID, attempt: Int = 0) async throws {
        guard let store = stores[name] else { return }
        let local = (known[name] ?? SyncDocument()).updated(with: store.syncItems(), normalize: store.normalized)
        known[name] = local
        let id = CKRecord.ID(recordName: name, zoneID: zone)
        var record: CKRecord
        var remote = SyncDocument()
        do {
            record = try await database.record(for: id)
            if let payload = record.encryptedValues["payload"] as? Data, let document = Self.document(from: payload) {
                remote = document
            }
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: Self.recordType, recordID: id)
        }
        let merged = SyncDocument.merge(local, remote)
        if merged.entries != local.entries {
            applying = true
            store.applySynced(merged.entries.mapValues(\.data))
            applying = false
        }
        known[name] = merged
        persist(lastSynced: nil)
        guard merged != remote else { return }
        guard let payload = Self.payload(for: merged) else {
            throw SyncError.tooLarge(name)
        }
        record.encryptedValues["payload"] = payload
        record["modified"] = Date() as NSDate
        do {
            _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged)
        } catch let error as CKError where error.code == .serverRecordChanged && attempt < 2 {
            // Another Mac saved in between: merge with what it saved, and try again.
            try await sync(name, in: database, zone: zone, attempt: attempt + 1)
        }
    }
    #endif

    private enum SyncError: LocalizedError {
        case tooLarge(String)

        var errorDescription: String? {
            switch self {
            case .tooLarge: String(localized: "There's too much to sync: iCloud keeps up to about a megabyte of each kind.")
            }
        }
    }

    nonisolated private static func payload(for document: SyncDocument) -> Data? {
        let json = SyncCoding.encode(document)
        guard let compressed = try? (json as NSData).compressed(using: .zlib) as Data, compressed.count <= maxPayload else { return nil }
        return compressed
    }

    nonisolated private static func document(from payload: Data) -> SyncDocument? {
        guard let json = try? (payload as NSData).decompressed(using: .zlib) as Data else { return nil }
        return SyncCoding.decode(SyncDocument.self, json)
    }

    private static func message(for error: Error) -> String {
        #if canImport(CloudKit)
        if let error = error as? CKError {
            switch error.code {
            case .networkUnavailable, .networkFailure: return String(localized: "iCloud can't be reached. Max Q tries again later.")
            case .quotaExceeded: return String(localized: "Your iCloud storage is full.")
            case .notAuthenticated: return String(localized: "Sign in to iCloud in System Settings to sync.")
            default: break
            }
        }
        #endif
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func persist(lastSynced: Date?) {
        var saved = Storage.load(Saved.self, from: Self.fileName) ?? Saved(known: [:], lastSynced: nil)
        saved.known = known
        if let lastSynced { saved.lastSynced = lastSynced }
        Storage.save(saved, to: Self.fileName)
    }

    /// Forgets what was synced (the stores keep their contents; iCloud keeps its copy).
    func forget() {
        known = [:]
        Storage.remove(Self.fileName)
    }
}
