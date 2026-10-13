//
//  Storage.swift
//  Max Q
//
//  Small JSON file store in Application Support (inside the app's sandbox container).
//  Writes are atomic and debounced by the callers.
//

import Foundation

enum Storage {
    nonisolated static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? mainIdentifier, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated private static let mainIdentifier = "com.myrhex.MaxQ"

    /// "Max Q". A copy built under another bundle identifier (a test copy, which runs outside the
    /// sandbox) keeps a folder of its own, so it never reads or overwrites the real app's tabs.
    nonisolated private static var folderName: String {
        let identifier = Bundle.main.bundleIdentifier ?? mainIdentifier
        return identifier == mainIdentifier ? "Max Q" : "Max Q (\(identifier))"
    }

    nonisolated static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        let url = directory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    nonisolated static func save<T: Encodable>(_ value: T, to name: String) {
        let url = directory.appendingPathComponent(name)
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            Log.app.error("Failed to save \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated static func remove(_ name: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }
}
