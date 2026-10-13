//
//  ArticleSpeaker.swift
//  Max Q
//
//  Reads a Grokipedia article aloud with the Mac's own voice, as grokipedia.com's Listen button
//  does: the title, then each section's heading and paragraphs in order, without the citation
//  numbers. One article at a time; it can pause, carry on, and stop, and it knows which section
//  it's reading so the contents can show it.
//

import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class ArticleSpeaker: NSObject {
    static let shared = ArticleSpeaker()

    /// The article being read, by its address.
    private(set) var article: URL?
    private(set) var paused = false
    /// The heading of the section being read.
    private(set) var section: String?

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    /// Which section each queued utterance belongs to.
    @ObservationIgnored private var sections: [ObjectIdentifier: String] = [:]
    @ObservationIgnored private var remaining = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func isReading(_ url: URL) -> Bool { article == url }

    /// Starts reading `article`, or pauses and carries on if it's the one being read.
    func toggle(_ card: GrokipediaCard, article content: GrokipediaArticle) {
        toggle(url: card.articleURL, title: card.title, article: content)
    }

    /// Starts reading the article at `url` (Grokipedia's, or a page in Reader), or pauses and
    /// carries on if it's the one being read.
    func toggle(url: URL, title: String, article content: GrokipediaArticle, language: String? = nil) {
        if article == url {
            if paused {
                synthesizer.continueSpeaking()
                paused = false
            } else {
                synthesizer.pauseSpeaking(at: .word)
                paused = true
            }
            return
        }
        stop()
        article = url
        paused = false
        // A voice in the article's own language (Grokipedia's are in English).
        let voice = AVSpeechSynthesisVoice(language: language ?? "en-US") ?? AVSpeechSynthesisVoice(language: "en-US")
        var current: String?
        func queue(_ text: String, pause: TimeInterval = 0.25) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let utterance = AVSpeechUtterance(string: trimmed)
            utterance.voice = voice
            utterance.postUtteranceDelay = pause
            if let current { sections[ObjectIdentifier(utterance)] = current }
            remaining += 1
            synthesizer.speak(utterance)
        }
        queue(title, pause: 0.5)
        for block in content.blocks {
            switch block {
            case .heading(let heading):
                current = heading.id
                queue(heading.text, pause: 0.45)
            case .paragraph(_, let runs), .quote(_, let runs):
                queue(Self.spoken(runs))
            case .list(_, _, let items):
                for item in items { queue(Self.spoken(item), pause: 0.15) }
            case .figure, .table:
                break
            }
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        sections = [:]
        remaining = 0
        article = nil
        paused = false
        section = nil
    }

    /// A paragraph's words, without its citation numbers.
    nonisolated static func spoken(_ runs: [GrokipediaRun]) -> String {
        runs.filter { if case .citation = $0.kind { false } else { true } }.map(\.text).joined()
    }
}

extension ArticleSpeaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            if let section = self.sections[id] { self.section = section }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            self.sections[id] = nil
            self.remaining -= 1
            if self.remaining <= 0, self.article != nil { self.stop() }
        }
    }
}
