//
//  Log.swift
//  Max Q
//

import OSLog

enum Log {
    nonisolated static let app = Logger(subsystem: "com.myrhex.MaxQ", category: "app")
    nonisolated static let browser = Logger(subsystem: "com.myrhex.MaxQ", category: "browser")
    nonisolated static let grok = Logger(subsystem: "com.myrhex.MaxQ", category: "grok")
}
