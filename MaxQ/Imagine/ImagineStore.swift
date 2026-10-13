//
//  ImagineStore.swift
//  Max Q
//
//  Imagine: pictures made by Grok's image models from a prompt, on the user's own key, with the
//  price shown before anything is made. Every picture is saved on this Mac (the API's own links
//  expire), with its prompt, so the page can show what was made before.
//

import AppKit
import Foundation
import Observation

/// A picture model and what one picture costs.
nonisolated struct ImageModelInfo: Codable, Equatable, Sendable {
    let id: String
    /// US dollars per picture, at the cheapest quality.
    var pricePerImage: Double?
}

extension GrokClient {
    /// The picture models this key can use, with their prices.
    nonisolated func imageModels() async throws -> [ImageModelInfo] {
        #if DEBUG
        if apiKey == Self.simulatedKey {
            return [ImageModelInfo(id: "grok-imagine-image", pricePerImage: 0.02),
                    ImageModelInfo(id: "grok-imagine-image-2.0", pricePerImage: 0.04)]
        }
        #endif
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("image-generation-models"))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data: data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let list = (json["models"] as? [[String: Any]]) ?? (json["data"] as? [[String: Any]]) ?? []
        return list.compactMap { model in
            guard let id = model["id"] as? String else { return nil }
            // Prices are in 1e-10 dollars (the cost ticks' unit), per tier; the cheapest one stands for the model.
            let tiers = (model["pricing"] as? [[String: Any]] ?? []).compactMap { ($0["price_per_image"] as? NSNumber)?.doubleValue }
            let price = tiers.min() ?? (model["image_price"] as? NSNumber)?.doubleValue
            return ImageModelInfo(id: id, pricePerImage: price.map { $0 / 1e10 })
        }
    }

    /// Makes `count` pictures for `prompt`. Returns them as image data, with what they cost.
    nonisolated func generateImages(prompt: String, model: String, count: Int, aspect: String) async throws -> (images: [Data], cost: Double?) {
        #if DEBUG
        if apiKey == Self.simulatedKey { return await Self.simulatedImages(prompt: prompt, count: count, aspect: aspect) }
        #endif
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("images/generations"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180
        let body: [String: Any] = ["model": model, "prompt": prompt, "n": max(1, min(count, 4)),
                                   "response_format": "b64_json", "aspect_ratio": aspect]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw GrokError.network(error.localizedDescription)
        }
        try Self.check(response, data: data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GrokError.badResponse("images")
        }
        let images = (json["data"] as? [[String: Any]] ?? []).compactMap { item -> Data? in
            (item["b64_json"] as? String).flatMap { Data(base64Encoded: $0) }
        }
        let cost = GrokUsage(json: json["usage"] as? [String: Any])?.costUSD
        guard !images.isEmpty else { throw GrokError.badResponse(String(localized: "No pictures came back.")) }
        return (images, cost)
    }

    #if DEBUG
    /// Pretend pictures for the simulator: soft gradients with the prompt on them.
    @MainActor
    private static func simulatedImages(prompt: String, count: Int, aspect: String) async -> (images: [Data], cost: Double?) {
        try? await Task.sleep(for: .milliseconds(1_400))
        let ratio = ImagineAspect(rawValue: aspect)?.ratio ?? 1
        let size = NSSize(width: 1024 * min(1, ratio), height: 1024 / max(1, ratio))
        let palettes: [(NSColor, NSColor)] = [(.systemIndigo, .systemPink), (.systemTeal, .systemBlue),
                                              (.systemOrange, .systemPurple), (.systemGreen, .systemYellow)]
        var images: [Data] = []
        for index in 0..<max(1, min(count, 4)) {
            let image = NSImage(size: size)
            image.lockFocus()
            let colors = palettes[index % palettes.count]
            NSGradient(starting: colors.0, ending: colors.1)?.draw(in: NSRect(origin: .zero, size: size), angle: 35 + Double(index) * 40)
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let text = NSAttributedString(string: "Simulated\n\(prompt.prefix(60))", attributes: [
                .font: NSFont.systemFont(ofSize: 44, weight: .semibold), .foregroundColor: NSColor.white.withAlphaComponent(0.9),
                .paragraphStyle: style,
            ])
            text.draw(in: NSRect(x: 60, y: size.height / 2 - 80, width: size.width - 120, height: 160))
            image.unlockFocus()
            if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                images.append(png)
            }
        }
        return (images, 0.02 * Double(images.count))
    }
    #endif
}

/// The shapes a picture can be made in.
nonisolated enum ImagineAspect: String, CaseIterable, Identifiable, Codable, Sendable {
    case square = "1:1", wide = "16:9", tall = "9:16", landscape = "4:3", portrait = "3:4"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .square: String(localized: "Square")
        case .wide: String(localized: "Wide")
        case .tall: String(localized: "Tall")
        case .landscape: String(localized: "Landscape")
        case .portrait: String(localized: "Portrait")
        }
    }

    /// Width over height.
    var ratio: Double {
        switch self {
        case .square: 1
        case .wide: 16.0 / 9
        case .tall: 9.0 / 16
        case .landscape: 4.0 / 3
        case .portrait: 3.0 / 4
        }
    }
}

/// One go: a prompt and the pictures it made.
nonisolated struct ImagineGeneration: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let prompt: String
    let created: Date
    let model: String
    let aspect: ImagineAspect
    /// The pictures' file names, in the Imagine folder.
    var files: [String] = []
    var cost: Double?
    var failure: String?
    var running = false
}

@MainActor
@Observable
final class ImagineStore {
    static let shared = ImagineStore()

    private(set) var generations: [ImagineGeneration] = []
    private(set) var models: [ImageModelInfo] = []
    /// A prompt to start with (from "!imagine …"), taken by the page when it appears.
    var draft: String?

    private static let fileName = "Imagine.json"

    nonisolated static var folder: URL {
        let folder = Storage.directory.appendingPathComponent("Imagine", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private init() {
        generations = (Storage.load([ImagineGeneration].self, from: Self.fileName) ?? []).map {
            var generation = $0
            generation.running = false
            return generation
        }
    }

    /// The cheaper model, and the better one when the key has it.
    var standardModel: String { models.first { $0.id == "grok-imagine-image" }?.id ?? models.first?.id ?? "grok-imagine-image" }
    var qualityModel: String? { models.first { $0.id == "grok-imagine-image-2.0" }?.id }

    func price(of model: String) -> Double {
        models.first { $0.id == model }?.pricePerImage ?? (model.contains("2.0") ? 0.04 : 0.02)
    }

    func loadModels() async {
        guard models.isEmpty, let client = GrokAccount.shared.client else { return }
        models = (try? await client.imageModels()) ?? []
    }

    func generate(_ prompt: String, count: Int, aspect: ImagineAspect, quality: Bool) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let client = GrokAccount.shared.client else { return }
        let model = quality ? (qualityModel ?? standardModel) : standardModel
        var generation = ImagineGeneration(id: UUID(), prompt: text, created: Date(), model: model, aspect: aspect)
        generation.running = true
        generations.insert(generation, at: 0)
        let id = generation.id
        Task { [weak self] in
            do {
                let result = try await client.generateImages(prompt: text, model: model, count: count, aspect: aspect.rawValue)
                var files: [String] = []
                for (index, data) in result.images.enumerated() {
                    let name = "\(id.uuidString)-\(index).\(Self.fileExtension(for: data))"
                    try? data.write(to: Self.folder.appendingPathComponent(name), options: .atomic)
                    files.append(name)
                }
                if let cost = result.cost { GrokAccount.shared.recordCost(cost, purpose: .image) }
                self?.update(id) {
                    $0.files = files
                    $0.cost = result.cost
                    $0.running = false
                }
            } catch {
                self?.update(id) {
                    $0.failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    $0.running = false
                }
            }
        }
    }

    func delete(_ id: UUID) {
        guard let generation = generations.first(where: { $0.id == id }) else { return }
        for file in generation.files { try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(file)) }
        generations.removeAll { $0.id == id }
        save()
    }

    func removeAll() {
        for generation in generations { delete(generation.id) }
        Storage.remove(Self.fileName)
    }

    func url(of file: String) -> URL { Self.folder.appendingPathComponent(file) }

    private func update(_ id: UUID, _ change: (inout ImagineGeneration) -> Void) {
        guard let index = generations.firstIndex(where: { $0.id == id }) else { return }
        change(&generations[index])
        save()
    }

    private func save() {
        let snapshot = generations.filter { !$0.running }
        Task.detached(priority: .utility) { Storage.save(snapshot, to: Self.fileName) }
    }

    nonisolated private static func fileExtension(for data: Data) -> String {
        data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "png" : (data.starts(with: [0x52, 0x49, 0x46, 0x46]) ? "webp" : "jpg")
    }
}
