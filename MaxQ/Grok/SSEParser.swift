//
//  SSEParser.swift
//  Max Q
//
//  Minimal Server-Sent Events parser for the streaming Responses API. Feed it lines, get events.
//  Pure logic, unit-tested.
//

import Foundation

nonisolated struct SSEEvent: Equatable {
    var event: String?
    var data: String
}

nonisolated struct SSEParser {
    private var eventName: String?
    private var dataLines: [String] = []

    /// Feeds one line (without its trailing newline). Returns an event when a blank line ends one.
    nonisolated mutating func feed(_ rawLine: String) -> SSEEvent? {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        if line.isEmpty {
            return flush()
        }
        if line.hasPrefix(":") { return nil }  // comment / keep-alive

        let field: String
        var value: String
        if let colon = line.firstIndex(of: ":") {
            field = String(line[..<colon])
            value = String(line[line.index(after: colon)...])
            if value.hasPrefix(" ") { value.removeFirst() }
        } else {
            field = line
            value = ""
        }

        switch field {
        case "event": eventName = value
        case "data": dataLines.append(value)
        default: break
        }
        return nil
    }

    /// Emits whatever is buffered (used at end of stream too).
    nonisolated mutating func flush() -> SSEEvent? {
        defer { eventName = nil; dataLines = [] }
        guard !dataLines.isEmpty else { return nil }
        return SSEEvent(event: eventName, data: dataLines.joined(separator: "\n"))
    }
}
