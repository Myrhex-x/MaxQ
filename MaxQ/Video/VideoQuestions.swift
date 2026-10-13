//
//  VideoQuestions.swift
//  Max Q
//
//  Asking Grok about the YouTube video in a tab. Max Q reads the video's transcript from YouTube's
//  own transcript panel once the user has opened it (YouTubeTranscript.js reads what the page
//  shows, nothing more is requested), sends it with the question, and Grok answers with the
//  moments it means as links: a click on [03:10] plays the video from there. Nothing is read until
//  the user asks.
//

import Foundation
import WebKit

/// A video's transcript, as the page script returns it.
nonisolated struct VideoTranscript: Equatable, Sendable {
    struct Segment: Equatable, Sendable {
        let start: Double
        let text: String
    }

    let videoID: String
    let title: String
    let author: String?
    let language: String?
    let length: Double?
    let segments: [Segment]

    /// "[03:10] what was said", in chunks of about `seconds`, kept under `limit` characters: a long
    /// video gets longer chunks rather than a cut-off ending.
    func lines(limit: Int = 80_000) -> String {
        var chunk: Double = 15
        while true {
            var lines: [String] = []
            var current: (start: Double, words: [String])?
            for segment in segments {
                if let open = current, segment.start - open.start < chunk {
                    current?.words.append(segment.text)
                } else {
                    if let open = current { lines.append("[\(Self.stamp(open.start))] " + open.words.joined(separator: " ")) }
                    current = (segment.start, [segment.text])
                }
            }
            if let open = current { lines.append("[\(Self.stamp(open.start))] " + open.words.joined(separator: " ")) }
            let text = lines.joined(separator: "\n")
            if text.count <= limit || chunk >= 240 { return String(text.prefix(limit)) }
            chunk *= 2
        }
    }

    /// 190 → "03:10", 3725 → "1:02:05".
    static func stamp(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600, minutes = total % 3600 / 60, secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%02d:%02d", minutes, secs)
    }
}

nonisolated enum VideoPages {
    /// The page is a YouTube video (a watch page, a Short, a live).
    static func isVideo(_ url: URL?) -> Bool {
        guard let url, let host = url.host?.lowercased(), host == "youtube.com" || host.hasSuffix(".youtube.com") else { return false }
        if url.path == "/watch" { return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "v" } ?? false }
        return ["/shorts/", "/live/"].contains { url.path.hasPrefix($0) }
    }

    /// The script that reads the transcript, from the app's resources, wrapped so a failure comes
    /// back as a reason rather than an exception.
    static let transcriptScript: String? = {
        guard let url = Bundle.main.url(forResource: "YouTubeTranscript", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return source + """

        try {
          const result = await maxqTranscript(options);
          return { ok: true, result: result };
        } catch (e) {
          return { ok: false, code: (e && e.code) || 'ERROR', message: String((e && e.message) || e) };
        }
        """
    }()

    /// Reads the transcript of the video on screen in `webView`.
    @MainActor
    static func transcript(in webView: WKWebView) async -> Result<VideoTranscript, VideoTranscriptError> {
        guard let script = transcriptScript else { return .failure(.unavailable("script")) }
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let raw = try? await webView.callAsyncJavaScript(script, arguments: ["options": ["language": language]],
                                                         in: nil, contentWorld: .defaultClient)
        guard let answer = raw as? [String: Any] else { return .failure(.unavailable("no answer")) }
        guard answer["ok"] as? Bool == true, let result = answer["result"] as? [String: Any] else {
            return .failure(VideoTranscriptError(code: answer["code"] as? String ?? "", message: answer["message"] as? String ?? ""))
        }
        let segments = (result["segments"] as? [[String: Any]] ?? []).compactMap { item -> VideoTranscript.Segment? in
            guard let text = item["text"] as? String, !text.isEmpty else { return nil }
            return VideoTranscript.Segment(start: (item["start"] as? NSNumber)?.doubleValue ?? 0, text: text)
        }
        guard !segments.isEmpty else { return .failure(.noCaptions) }
        return .success(VideoTranscript(videoID: result["videoId"] as? String ?? "",
                                        title: result["title"] as? String ?? webView.title ?? "",
                                        author: result["author"] as? String,
                                        language: result["language"] as? String,
                                        length: (result["lengthSeconds"] as? NSNumber)?.doubleValue,
                                        segments: segments))
    }

    /// Plays the video in `webView` from `seconds`.
    @MainActor
    static func seek(_ webView: WKWebView, to seconds: Double) async {
        _ = await PageScripts.run("""
        var v = document.querySelector('video');
        if (!v) return false;
        v.currentTime = seconds;
        try { await v.play(); } catch (e) {}
        return true;
        """, arguments: ["seconds": seconds], in: webView)
    }
}

nonisolated enum VideoTranscriptError: Error, Equatable {
    /// YouTube's transcript panel isn't open: Max Q reads only what the page shows.
    case panelClosed
    case noCaptions
    case unplayable
    case blocked
    case unavailable(String)

    init(code: String, message: String) {
        switch code {
        case "PANEL_CLOSED": self = .panelClosed
        case "NO_CAPTIONS", "EMPTY_TRANSCRIPT": self = .noCaptions
        case "UNPLAYABLE", "NOT_A_VIDEO_PAGE": self = .unplayable
        case "LOGIN_REQUIRED", "RATE_LIMITED": self = .blocked
        default: self = .unavailable(message)
        }
    }

    var message: String {
        switch self {
        case .panelClosed: String(localized: "Open the video's transcript first: under the video, click …more, then Show transcript. Then ask again.")
        case .noCaptions: String(localized: "This video has no transcript, so Grok can't tell what's said in it.")
        case .unplayable: String(localized: "This video can't be played here, so there's no transcript to read.")
        case .blocked: String(localized: "YouTube didn't give the transcript right now. Try again in a moment.")
        case .unavailable: String(localized: "The video's transcript didn't load.")
        }
    }
}
