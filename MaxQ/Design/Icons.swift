//
//  Icons.swift
//  Max Q
//
//  Max Q's own icon set, drawn in the manner of SpaceXAI's interfaces: a 24-point grid, 2-point
//  strokes cut square at the ends, mitered corners on straight glyphs and soft corners on boxes.
//  Every glyph here is original to Max Q (no SpaceXAI, X or Apple artwork) and scales cleanly from
//  12 to 32 points. Defined as SVG-style path strings so each one stays readable and easy to tune.
//

import SwiftUI

enum MQIcon: String, CaseIterable, Sendable {
    case plus, minus, close, check
    case chevronDown, chevronUp, chevronLeft, chevronRight, chevronUpDown
    case arrowUp, arrowLeft, arrowRight, arrowUpRight
    case reload, stop, search, zoomIn, zoomOut
    case sidebar, share, more, gear, ghost, lock, warning, globe, book
    case bubble, translate, lines, link, copy, envelope, mic, video, clock, speaker
    case bolt, image, download, trash, key, sun, moon, system, compose, stack, doc
    case returnKey, info, shield, house, attach, eye, flag, command
    case heart, repost, views, cornerDownRight
    case cloud, cloudSun, cloudMoon, rain, drizzle, snow, storm, fog
    case shieldOff, splitView
    case people, play, sealCheck, quote, calendar
    case columns, bell, bellFill, speakerOff, pip, pointer

    /// Glyph parts in the 24-point grid.
    fileprivate var parts: [IconPart] {
        switch self {
        case .plus: [.stroke("M12 4.5V19.5 M4.5 12H19.5")]
        case .minus: [.stroke("M4.5 12H19.5")]
        case .close: [.stroke("M6.25 6.25L17.75 17.75 M17.75 6.25L6.25 17.75")]
        case .check: [.stroke("M4.75 12.5L9.5 17.25L19.25 7.5")]
        case .chevronDown: [.stroke("M5.75 9.25L12 15.5L18.25 9.25")]
        case .chevronUp: [.stroke("M5.75 14.75L12 8.5L18.25 14.75")]
        case .chevronLeft: [.stroke("M14.75 5.75L8.5 12L14.75 18.25")]
        case .chevronRight: [.stroke("M9.25 5.75L15.5 12L9.25 18.25")]
        case .chevronUpDown: [.stroke("M7.75 9.25L12 5L16.25 9.25 M7.75 14.75L12 19L16.25 14.75")]
        case .arrowUp: [.stroke("M12 19.75V5.25 M5.5 11.75L12 5.25L18.5 11.75")]
        case .arrowLeft: [.stroke("M19.75 12H5.25 M11.75 5.5L5.25 12L11.75 18.5")]
        case .arrowRight: [.stroke("M4.25 12H18.75 M12.25 5.5L18.75 12L12.25 18.5")]
        case .arrowUpRight: [.stroke("M6.75 17.25L16.5 7.5 M8.25 6.75H17.25V15.75")]
        case .reload:
            [.stroke("M19.25 12A7.25 7.25 0 1 1 16.95 6.7 M18.25 2.75V7.5H13.5")]
        case .stop: [.fill("M8.5 7H15.5A1.5 1.5 0 0 1 17 8.5V15.5A1.5 1.5 0 0 1 15.5 17H8.5A1.5 1.5 0 0 1 7 15.5V8.5A1.5 1.5 0 0 1 8.5 7Z")]
        case .search: [.stroke(circle(10.75, 10.75, 6.5) + " M15.5 15.5L20.25 20.25")]
        case .zoomIn: [.stroke(circle(10.75, 10.75, 6.5) + " M15.5 15.5L20.25 20.25 M8 10.75H13.5 M10.75 8V13.5")]
        case .zoomOut: [.stroke(circle(10.75, 10.75, 6.5) + " M15.5 15.5L20.25 20.25 M8 10.75H13.5")]
        case .sidebar:
            [.stroke(roundRect(3, 4.5, 18, 15, 3) + " M9.5 4.5V19.5")]
        case .share:
            [.stroke("M12 14.5V3.75 M7.75 8L12 3.75L16.25 8 M8.75 10.75H7A2 2 0 0 0 5 12.75V18.5A2 2 0 0 0 7 20.5H17A2 2 0 0 0 19 18.5V12.75A2 2 0 0 0 17 10.75H15.25")]
        case .more:
            [.fill(circle(5.5, 12, 1.75) + " " + circle(12, 12, 1.75) + " " + circle(18.5, 12, 1.75))]
        case .gear: [.stroke(Self.gearOutline + " " + circle(12, 12, 3))]
        case .ghost:
            [.stroke("M5.5 20.25V11.5A6.5 6.5 0 0 1 18.5 11.5V20.25L16.25 18.5L14.1 20.25L12 18.5L9.9 20.25L7.75 18.5Z"),
             .fill(ellipse(9.75, 11.5, 1.25, 1.6) + " " + ellipse(14.25, 11.5, 1.25, 1.6))]
        case .lock:
            [.stroke(roundRect(4.75, 10.5, 14.5, 10, 2) + " M8.25 10.5V7.75A3.75 3.75 0 0 1 15.75 7.75V10.5")]
        case .warning:
            [.stroke("M12 4L21.25 19.75H2.75Z M12 9.75V14.25"), .fill(circle(12, 17.1, 1.15))]
        case .globe:
            [.stroke(circle(12, 12, 8.75) + " M3.25 12H20.75 M12 3.25C9.75 5.75 8.6 8.75 8.6 12C8.6 15.25 9.75 18.25 12 20.75C14.25 18.25 15.4 15.25 15.4 12C15.4 8.75 14.25 5.75 12 3.25Z")]
        case .book:
            [.stroke("M12 6.75C10.25 5.4 7.75 4.75 3.75 4.75V18.5C7.75 18.5 10.25 19.15 12 20.5C13.75 19.15 16.25 18.5 20.25 18.5V4.75C16.25 4.75 13.75 5.4 12 6.75Z M12 6.75V20.5")]
        case .bubble:
            [.stroke("M6.25 4.75H17.75A2.5 2.5 0 0 1 20.25 7.25V14.75A2.5 2.5 0 0 1 17.75 17.25H11.75L7.25 20.5V17.25H6.25A2.5 2.5 0 0 1 3.75 14.75V7.25A2.5 2.5 0 0 1 6.25 4.75Z M8 9.5H16 M8 12.75H13")]
        case .translate:
            [.stroke("M3.25 6.25H11.75 M7.5 3.5V6.25 M5.25 6.25C5.9 9.25 7.9 11.5 11 12.75 M9.75 6.25C9.15 9.4 6.9 11.9 3.75 13.25 M12.75 20.75L16.75 10.75L20.75 20.75 M14.15 17.25H19.35")]
        case .lines: [.stroke("M4.5 6.5H19.5 M4.5 10.5H19.5 M4.5 14.5H15.5 M4.5 18.5H11.5")]
        case .link:
            [.stroke("M9.9 14.1L14.1 9.9 M8.75 11.4L6.9 13.25A3.7 3.7 0 0 0 12.15 18.5L14 16.65 M15.25 12.6L17.1 10.75A3.7 3.7 0 0 0 11.85 5.5L10 7.35")]
        case .copy:
            [.stroke(roundRect(8.25, 8.25, 12, 12, 2) + " M15.75 8.25V5.75A2 2 0 0 0 13.75 3.75H5.75A2 2 0 0 0 3.75 5.75V13.75A2 2 0 0 0 5.75 15.75H8.25")]
        case .envelope:
            [.stroke(roundRect(3.25, 5.25, 17.5, 13.5, 2.5) + " M4 7.5L12 13.25L20 7.5")]
        case .mic:
            [.stroke(roundRect(9, 3.25, 6, 11.5, 3) + " M5.75 11A6.25 6.25 0 0 0 18.25 11 M12 17.25V20.75")]
        case .video:
            [.stroke(roundRect(3.25, 6.25, 12, 11.5, 2) + " M15.25 10.25L20.75 7.25V16.75L15.25 13.75")]
        case .clock: [.stroke(circle(12, 12, 8.75) + " M12 7.25V12L15.25 14.25")]
        case .speaker:
            [.stroke("M3.75 9.25H7.25L11.75 5.5V18.5L7.25 14.75H3.75Z M15.25 9.25A3.75 3.75 0 0 1 15.25 14.75 M17.75 6.5A7.5 7.5 0 0 1 17.75 17.5")]
        case .bolt:
            [.stroke("M13.25 3.25L5.25 13.5H11.25L10.5 20.75L18.75 10.5H12.75Z", join: .round)]
        case .image:
            [.stroke(roundRect(3.25, 4.25, 17.5, 15.5, 2.5) + " " + circle(15.25, 9.25, 1.6) + " M3.75 16.5L8.75 12L12.75 15.5L15.25 13.5L20.25 17.5")]
        case .download: [.stroke("M12 3.75V15 M7 10.25L12 15.25L17 10.25 M4.75 20.25H19.25")]
        case .trash:
            [.stroke("M4.25 6.75H19.75 M9.25 6.75V4.25H14.75V6.75 M6.5 6.75L7.5 20.25H16.5L17.5 6.75 M10.25 10.75V16.25 M13.75 10.75V16.25")]
        case .key:
            [.stroke(circle(8.25, 15.75, 4) + " M11.1 12.9L19.75 4.25 M16.75 7.25L19.25 9.75 M14.25 9.75L16.25 11.75")]
        case .sun:
            [.stroke(circle(12, 12, 3.75) + " M12 2.75V5 M12 19V21.25 M2.75 12H5 M19 12H21.25 M5.45 5.45L7.05 7.05 M16.95 16.95L18.55 18.55 M5.45 18.55L7.05 16.95 M16.95 7.05L18.55 5.45")]
        case .moon:
            [.stroke("M19.75 14.25A8.25 8.25 0 1 1 9.75 4.25A6.5 6.5 0 0 0 19.75 14.25Z")]
        case .system:
            [.stroke(circle(12, 12, 8.5)), .fill("M12 3.5A8.5 8.5 0 0 0 12 20.5Z")]
        case .compose:
            [.stroke("M11.75 4.25H6.25A2 2 0 0 0 4.25 6.25V17.75A2 2 0 0 0 6.25 19.75H17.75A2 2 0 0 0 19.75 17.75V12.25 M17.5 3.5L20.5 6.5L12.25 14.75H9.25V11.75Z")]
        case .stack:
            [.stroke(roundRect(4.25, 8.25, 11.5, 11.5, 2) + " M8.25 8.25V6.25A2 2 0 0 1 10.25 4.25H17.75A2 2 0 0 1 19.75 6.25V13.75A2 2 0 0 1 17.75 15.75H15.75")]
        case .doc:
            [.stroke("M6.75 3.25H13.75L18.75 8.25V18.75A2 2 0 0 1 16.75 20.75H6.75A2 2 0 0 1 4.75 18.75V5.25A2 2 0 0 1 6.75 3.25Z M13.75 3.25V8.25H18.75 M8.5 12.75H15 M8.5 16.25H13")]
        case .returnKey: [.stroke("M19.25 5.25V12.75H5.75 M9.75 8.75L5.75 12.75L9.75 16.75")]
        case .info: [.stroke(circle(12, 12, 8.75) + " M12 10.75V16.5"), .fill(circle(12, 7.85, 1.15))]
        case .shield: [.stroke("M12 3.25L19.25 6.25V11.5C19.25 15.6 16.25 18.9 12 20.75C7.75 18.9 4.75 15.6 4.75 11.5V6.25Z")]
        case .splitView:
            [.stroke(roundRect(3, 4.5, 18, 15, 3) + " M12 4.5V19.5")]
        case .shieldOff:
            [.stroke("M12 3.25L19.25 6.25V11.5C19.25 15.6 16.25 18.9 12 20.75C7.75 18.9 4.75 15.6 4.75 11.5V6.25Z M3.75 3.75L20.25 20.25")]
        case .house:
            [.stroke("M4.25 10.25L12 4L19.75 10.25V18.75A2 2 0 0 1 17.75 20.75H6.25A2 2 0 0 1 4.25 18.75Z M9.75 20.75V14.75H14.25V20.75")]
        case .attach:
            [.stroke("M19.25 11.25L12.4 18.1A4.25 4.25 0 0 1 6.4 12.1L13.55 4.95A2.85 2.85 0 0 1 17.6 9L10.65 15.95A1.4 1.4 0 0 1 8.7 13.95L14.9 7.75")]
        case .eye:
            [.stroke("M2.75 12C5.15 7.75 8.35 5.75 12 5.75C15.65 5.75 18.85 7.75 21.25 12C18.85 16.25 15.65 18.25 12 18.25C8.35 18.25 5.15 16.25 2.75 12Z " + circle(12, 12, 3))]
        case .flag: [.stroke("M5.75 21V4.25H18.75L15.75 8.75L18.75 13.25H5.75")]
        case .heart:
            [.stroke("M12 19.5C12 19.5 4 15.1 4 9.25C4 6.75 5.9 4.75 8.3 4.75C9.9 4.75 11.2 5.6 12 6.95C12.8 5.6 14.1 4.75 15.7 4.75C18.1 4.75 20 6.75 20 9.25C20 15.1 12 19.5 12 19.5Z", join: .round)]
        case .repost:
            [.stroke("M7.25 4.5L4.25 7.5L7.25 10.5 M4.75 7.5H15.75A3.5 3.5 0 0 1 19.25 11V12 M16.75 19.5L19.75 16.5L16.75 13.5 M19.25 16.5H8.25A3.5 3.5 0 0 1 4.75 13V12")]
        case .views:
            [.stroke("M5.75 19.25V13.25 M10 19.25V8.75 M14.25 19.25V4.75 M18.5 19.25V11.25")]
        case .cornerDownRight:
            [.stroke("M5.75 4.75V11.25A3 3 0 0 0 8.75 14.25H18.75 M14.75 10.25L18.75 14.25L14.75 18.25")]
        // Weather: a cloud of three lobes on a flat base, alone or over rain, snow or a bolt.
        case .cloud: [.stroke("M7.50 18.50A3.25 3.25 0 1 1 7.51 12.00A4.75 4.75 0 0 1 16.94 11.00A3.75 3.75 0 0 1 16.75 18.50H7.50Z", join: .round)]
        case .cloudSun:
            [.stroke("M9.25 20.25A3.25 3.25 0 1 1 9.26 13.75A4.75 4.75 0 0 1 18.69 12.75A3.75 3.75 0 0 1 18.50 20.25H9.25Z", join: .round),
             .stroke("M12.23 9.09A3.25 3.25 0 1 0 9.12 12.88 M4.00 8.75L2.15 8.75 M5.46 5.21L4.16 3.91 M9.00 3.75L9.00 1.90 M12.54 5.21L13.84 3.91")]
        case .cloudMoon:
            [.stroke("M9.25 20.25A3.25 3.25 0 1 1 9.26 13.75A4.75 4.75 0 0 1 18.69 12.75A3.75 3.75 0 0 1 18.50 20.25H9.25Z", join: .round), .stroke("M4.6 9.6A4.6 4.6 0 0 0 11.9 6.2A3.6 3.6 0 0 1 4.6 9.6Z", join: .round)]
        case .rain: [.stroke("M7.50 15.75A3.25 3.25 0 1 1 7.51 9.25A4.75 4.75 0 0 1 16.94 8.25A3.75 3.75 0 0 1 16.75 15.75H7.50Z", join: .round), .stroke("M8.5 18.25L7.25 21 M12.5 18.25L11.25 21 M16.5 18.25L15.25 21")]
        case .drizzle: [.stroke("M7.50 15.75A3.25 3.25 0 1 1 7.51 9.25A4.75 4.75 0 0 1 16.94 8.25A3.75 3.75 0 0 1 16.75 15.75H7.50Z", join: .round), .stroke("M9 18.5L8.4 20 M13 19.25L12.4 20.75 M16.75 18.5L16.15 20")]
        case .snow:
            [.stroke("M7.50 15.75A3.25 3.25 0 1 1 7.51 9.25A4.75 4.75 0 0 1 16.94 8.25A3.75 3.75 0 0 1 16.75 15.75H7.50Z", join: .round),
             .fill(circle(8.5, 19.5, 1.05) + " " + circle(12.5, 20.75, 1.05) + " " + circle(16.25, 19.5, 1.05))]
        case .storm: [.stroke("M7.50 15.75A3.25 3.25 0 1 1 7.51 9.25A4.75 4.75 0 0 1 16.94 8.25A3.75 3.75 0 0 1 16.75 15.75H7.50Z", join: .round), .stroke("M12.75 16.25L10.5 19.5H13.5L11.25 22.75", join: .round)]
        case .fog: [.stroke("M4.25 9.25H19.75 M6.25 13.25H17.75 M4.25 17.25H15.75")]
        case .command:
            [.stroke("M9 9V6.75A2.25 2.25 0 1 0 6.75 9H17.25A2.25 2.25 0 1 0 15 6.75V17.25A2.25 2.25 0 1 0 17.25 15H6.75A2.25 2.25 0 1 0 9 17.25Z")]
        // Two people, one a step behind the other: context added by readers.
        case .people:
            [.stroke(circle(9, 8.25, 3.25) + " M3.25 19.25C3.25 15.9 5.85 13.75 9 13.75C12.15 13.75 14.75 15.9 14.75 19.25 M15.25 5.25A3.25 3.25 0 0 1 15.25 11.25 M17.25 13.95C19.35 14.6 20.75 16.6 20.75 19.25", join: .round)]
        // A soft-cornered play triangle, filled.
        case .play:
            [.fill("M8.25 5.6C8.25 4.85 9.05 4.38 9.71 4.75L19.02 10.15C19.67 10.53 19.67 11.47 19.02 11.85L9.71 17.25C9.05 17.62 8.25 17.15 8.25 16.4Z")]
        // A seal with a check: something checked and stamped.
        case .sealCheck:
            [.stroke("M12 2.9L14.2 4.5L16.9 4.35L17.75 6.95L20.05 8.35L19.25 10.95L20.05 13.55L17.75 14.95L16.9 17.55L14.2 17.4L12 19L9.8 17.4L7.1 17.55L6.25 14.95L3.95 13.55L4.75 10.95L3.95 8.35L6.25 6.95L7.1 4.35L9.8 4.5Z M8.75 11L11.1 13.35L15.5 8.95", join: .round)]
        // An opening quotation mark, for a post quoting another.
        case .quote:
            [.fill("M5 12.6C5 9.2 6.9 6.6 10.1 5.5L10.75 6.75C8.95 7.6 7.95 8.95 7.8 10.6H10.25V17.25H5Z M13.75 12.6C13.75 9.2 15.65 6.6 18.85 5.5L19.5 6.75C17.7 7.6 16.7 8.95 16.55 10.6H19V17.25H13.75Z")]
        case .bell:
            [.stroke("M6.25 16.25V11.25A5.75 5.75 0 0 1 17.75 11.25V16.25L19.25 17.75H4.75Z M10 20.5H14", join: .round)]
        case .bellFill:
            [.fill("M6.25 16.25V11.25A5.75 5.75 0 0 1 17.75 11.25V16.25L19.25 17.75H4.75Z"), .stroke("M10 20.5H14", join: .round)]
        case .speakerOff:
            [.stroke("M3.75 9.25H7.25L11.75 5.5V18.5L7.25 14.75H3.75Z M15.25 9.75L20.25 14.75 M20.25 9.75L15.25 14.75")]
        case .pip:
            [.stroke(roundRect(3.25, 5.25, 17.5, 13.5, 2.5)), .fill("M12.75 12.25H18A0.75 0.75 0 0 1 18.75 13V16A0.75 0.75 0 0 1 18 16.75H12.75A0.75 0.75 0 0 1 12 16V13A0.75 0.75 0 0 1 12.75 12.25Z")]
        case .columns:
            [.stroke("M3.75 9.25L12 4.5L20.25 9.25Z M6.5 9.75V16.75 M10.25 9.75V16.75 M13.75 9.75V16.75 M17.5 9.75V16.75 M4.75 17.25H19.25 M3.75 19.75H20.25", join: .round)]
        case .calendar:
            [.stroke(roundRect(3.75, 5.25, 16.5, 15, 2.5) + " M3.75 10.25H20.25 M8.25 3.25V7.25 M15.75 3.25V7.25")]
        case .pointer:
            [.stroke("M6.25 3.75V18.25L10.1 14.6L12.75 20.25L15.25 19.1L12.6 13.5L17.75 13.25Z", join: .round)]
        }
    }

    /// All of the glyph's path data in one string (for checks and previews).
    var pathData: String {
        parts.map { part in
            switch part {
            case .stroke(let d, _): d
            case .fill(let d): d
            }
        }
        .joined(separator: " ")
    }

    /// An eight-tooth gear with flat-topped teeth.
    private static let gearOutline: String = {
        let center = 12.0, outer = 9.6, inner = 7.25
        var commands: [String] = []
        for tooth in 0..<8 {
            let angle = Double(tooth) * .pi / 4 - .pi / 2
            let points: [(Double, Double)] = [
                (inner, angle - 0.33), (outer, angle - 0.2), (outer, angle + 0.2), (inner, angle + 0.33),
            ]
            for (index, point) in points.enumerated() {
                let x = center + point.0 * cos(point.1), y = center + point.0 * sin(point.1)
                let verb = tooth == 0 && index == 0 ? "M" : "L"
                commands.append(String(format: "%@%.3f %.3f", verb, x, y))
            }
        }
        return commands.joined(separator: " ") + "Z"
    }()
}

// MARK: - Drawing

fileprivate enum IconPart {
    case stroke(String, join: CGLineJoin = .miter)
    case fill(String)
}

fileprivate func circle(_ cx: Double, _ cy: Double, _ r: Double) -> String {
    ellipse(cx, cy, r, r)
}

fileprivate func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> String {
    "M\(cx - rx) \(cy)A\(rx) \(ry) 0 1 0 \(cx + rx) \(cy)A\(rx) \(ry) 0 1 0 \(cx - rx) \(cy)Z"
}

fileprivate func roundRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) -> String {
    "M\(x + r) \(y)H\(x + w - r)A\(r) \(r) 0 0 1 \(x + w) \(y + r)V\(y + h - r)A\(r) \(r) 0 0 1 \(x + w - r) \(y + h)H\(x + r)A\(r) \(r) 0 0 1 \(x) \(y + h - r)V\(y + r)A\(r) \(r) 0 0 1 \(x + r) \(y)Z"
}

/// Parsed glyphs, cached once per icon.
@MainActor
private enum IconCache {
    static var strokes: [MQIcon: [(Path, CGLineJoin)]] = [:]
    static var fills: [MQIcon: Path] = [:]

    static func load(_ icon: MQIcon) -> (strokes: [(Path, CGLineJoin)], fill: Path?) {
        if let strokes = strokes[icon] { return (strokes, fills[icon]) }
        var strokeParts: [(Path, CGLineJoin)] = []
        var fill: Path?
        for part in icon.parts {
            switch part {
            case .stroke(let d, let join): strokeParts.append((SVGPath.parse(d), join))
            case .fill(let d):
                var path = fill ?? Path()
                path.addPath(SVGPath.parse(d))
                fill = path
            }
        }
        strokes[icon] = strokeParts
        fills[icon] = fill
        return (strokeParts, fill)
    }
}

/// One glyph at a given size. Inherits the foreground style. `weight` is in grid points (2 is
/// the house weight; 1.75 reads lighter at large sizes).
struct Icon: View {
    let icon: MQIcon
    var size: CGFloat = 18
    var weight: CGFloat = 2

    init(_ icon: MQIcon, size: CGFloat = 18, weight: CGFloat = 2) {
        self.icon = icon
        self.size = size
        self.weight = weight
    }

    var body: some View {
        let glyph = IconCache.load(icon)
        let scale = size / 24
        ZStack {
            ForEach(Array(glyph.strokes.enumerated()), id: \.offset) { _, part in
                GridShape(path: part.0)
                    .stroke(style: StrokeStyle(lineWidth: weight * scale, lineCap: .butt, lineJoin: part.1, miterLimit: 6))
            }
            if let fill = glyph.fill {
                GridShape(path: fill).fill()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A 24-point grid path scaled into its frame.
struct GridShape: Shape {
    let path: Path

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        return path.applying(CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}

// MARK: - SVG path parsing

/// A small SVG path-data parser: M L H V C S Q T A Z, absolute and relative.
nonisolated enum SVGPath {
    static func parse(_ data: String) -> Path {
        var path = Path()
        var scanner = Scanner(data)
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastCubicControl: CGPoint?
        var lastQuadControl: CGPoint?
        var command: Character = "M"

        while let next = scanner.nextCommandOrNumber() {
            if case .command(let letter) = next {
                command = letter
                if letter == "Z" || letter == "z" {
                    path.closeSubpath()
                    current = subpathStart
                    lastCubicControl = nil
                    lastQuadControl = nil
                    continue
                }
            } else {
                scanner.rewind()
            }

            let relative = command.isLowercase
            func point() -> CGPoint? {
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }

            switch command.uppercased().first! {
            case "M":
                guard let p = point() else { return path }
                path.move(to: p)
                current = p
                subpathStart = p
                // Further pairs after a moveto are implicit linetos.
                command = relative ? "l" : "L"
                lastCubicControl = nil
                lastQuadControl = nil
            case "L":
                guard let p = point() else { return path }
                path.addLine(to: p)
                current = p
                lastCubicControl = nil
                lastQuadControl = nil
            case "H":
                guard let x = scanner.number() else { return path }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
                lastCubicControl = nil
                lastQuadControl = nil
            case "V":
                guard let y = scanner.number() else { return path }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
                lastCubicControl = nil
                lastQuadControl = nil
            case "C":
                guard let c1 = point(), let c2 = point(), let p = point() else { return path }
                path.addCurve(to: p, control1: c1, control2: c2)
                current = p
                lastCubicControl = c2
                lastQuadControl = nil
            case "S":
                guard let c2 = point(), let p = point() else { return path }
                let c1 = lastCubicControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                path.addCurve(to: p, control1: c1, control2: c2)
                current = p
                lastCubicControl = c2
                lastQuadControl = nil
            case "Q":
                guard let c = point(), let p = point() else { return path }
                path.addQuadCurve(to: p, control: c)
                current = p
                lastQuadControl = c
                lastCubicControl = nil
            case "T":
                guard let p = point() else { return path }
                let c = lastQuadControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                path.addQuadCurve(to: p, control: c)
                current = p
                lastQuadControl = c
                lastCubicControl = nil
            case "A":
                guard let rx = scanner.number(), let ry = scanner.number(), let rotation = scanner.number(),
                      let largeArc = scanner.number(), let sweep = scanner.number(), let p = point() else { return path }
                addArc(to: &path, from: current, to: p, rx: rx, ry: ry, rotation: rotation,
                       largeArc: largeArc != 0, sweep: sweep != 0)
                current = p
                lastCubicControl = nil
                lastQuadControl = nil
            default:
                return path
            }
        }
        return path
    }

    /// SVG elliptical arc, converted to cubic Béziers (SVG 1.1 implementation notes, F.6.5).
    private static func addArc(to path: inout Path, from p0: CGPoint, to p1: CGPoint,
                               rx rxIn: Double, ry ryIn: Double, rotation: Double,
                               largeArc: Bool, sweep: Bool) {
        var rx = abs(rxIn), ry = abs(ryIn)
        guard rx > 0, ry > 0, p0 != p1 else {
            path.addLine(to: p1)
            return
        }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            rx *= sqrt(lambda)
            ry *= sqrt(lambda)
        }
        let numerator = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coefficient = sqrt(max(0, numerator / denominator))
        if largeArc == sweep { coefficient = -coefficient }
        let cxp = coefficient * rx * y1p / ry
        let cyp = -coefficient * ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let dot = ux * vx + uy * vy
            let length = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            var value = acos(max(-1, min(1, dot / length)))
            if ux * vy - uy * vx < 0 { value = -value }
            return value
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / Double(segments)
        let k = 4.0 / 3.0 * tan(step / 4)
        var theta = theta1
        func ellipsePoint(_ t: Double) -> CGPoint {
            CGPoint(x: cx + rx * cos(t) * cosPhi - ry * sin(t) * sinPhi,
                    y: cy + rx * cos(t) * sinPhi + ry * sin(t) * cosPhi)
        }
        func derivative(_ t: Double) -> CGPoint {
            CGPoint(x: -rx * sin(t) * cosPhi - ry * cos(t) * sinPhi,
                    y: -rx * sin(t) * sinPhi + ry * cos(t) * cosPhi)
        }
        for _ in 0..<segments {
            let next = theta + step
            let start = ellipsePoint(theta), end = ellipsePoint(next)
            let d1 = derivative(theta), d2 = derivative(next)
            path.addCurve(to: end,
                          control1: CGPoint(x: start.x + k * d1.x, y: start.y + k * d1.y),
                          control2: CGPoint(x: end.x - k * d2.x, y: end.y - k * d2.y))
            theta = next
        }
    }

    private struct Scanner {
        enum Token { case command(Character), number(Double) }
        private let characters: [Character]
        private var index = 0
        private var lastIndex = 0

        init(_ text: String) { characters = Array(text) }

        mutating func rewind() { index = lastIndex }

        mutating func nextCommandOrNumber() -> Token? {
            skipSeparators()
            lastIndex = index
            guard index < characters.count else { return nil }
            let character = characters[index]
            if character.isLetter {
                index += 1
                return .command(character)
            }
            return number().map { .number($0) }
        }

        mutating func number() -> Double? {
            skipSeparators()
            let start = index
            if index < characters.count, characters[index] == "-" || characters[index] == "+" { index += 1 }
            var sawDot = false
            while index < characters.count {
                let character = characters[index]
                if character.isNumber {
                    index += 1
                } else if character == ".", !sawDot {
                    sawDot = true
                    index += 1
                } else if character == "e" || character == "E" {
                    index += 1
                    if index < characters.count, characters[index] == "-" || characters[index] == "+" { index += 1 }
                } else {
                    break
                }
            }
            guard index > start else { return nil }
            return Double(String(characters[start..<index]))
        }

        private mutating func skipSeparators() {
            while index < characters.count, characters[index] == " " || characters[index] == "," || characters[index] == "\n" {
                index += 1
            }
        }
    }
}
