//
//  Calculator.swift
//  Max Q
//
//  Arithmetic typed into the search field ("12*7+3", "15% of 240", "sqrt(2)", "2^10"), worked
//  out on this Mac. A small parser of its own: Foundation's NSExpression throws Objective-C
//  exceptions on bad input, which would crash the app. Pure logic, unit-tested.
//

import Foundation

nonisolated enum Calculator {
    /// The expression's value, when `text` is arithmetic worth answering: something to work out,
    /// not a lone number, a date or a phone number.
    static func evaluate(_ text: String, decimalSeparator: String = Locale.current.decimalSeparator ?? ".") -> Double? {
        guard let source = normalize(text, decimalSeparator: decimalSeparator) else { return nil }
        var parser = Parser(tokens: tokenize(source))
        guard !parser.tokens.isEmpty, let value = parser.parseExpression(), parser.atEnd, value.isFinite else { return nil }
        guard parser.didWork else { return nil }
        return value
    }

    /// The expression as Max Q shows it above the result: "12 × 7 + 3".
    static func display(_ text: String) -> String {
        var shown = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if shown.hasSuffix("=") { shown.removeLast() }
        shown = shown.replacingOccurrences(of: "*", with: " × ")
            .replacingOccurrences(of: "/", with: " ÷ ")
            .replacingOccurrences(of: "+", with: " + ")
        // A minus between two things is subtraction; at the start or after an operator, a sign.
        shown = shown.replacingOccurrences(of: #"(?<=[\d)])\s*-\s*"#, with: " − ", options: .regularExpression)
        return shown.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Normalizing

    static func normalize(_ text: String, decimalSeparator: String) -> String? {
        var s = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["what is ", "what's ", "calculate ", "calc ", "combien font ", "combien fait "] where s.hasPrefix(prefix) {
            s.removeFirst(prefix.count)
        }
        while s.hasSuffix("=") || s.hasSuffix("?") { s.removeLast() }
        s = s.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, s.count <= 120, s.contains(where: \.isNumber) else { return nil }
        // Dates and phone numbers aren't sums: "2026-10-10", "10/10/2026", "555-1234".
        if s.range(of: #"^\d{1,4}[-/.]\d{1,2}[-/.]\d{1,4}$"#, options: .regularExpression) != nil { return nil }
        if s.range(of: #"^\d+-\d+$"#, options: .regularExpression) != nil { return nil }

        s = s.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "π", with: "pi")
            .replacingOccurrences(of: "√", with: "sqrt")
            .replacingOccurrences(of: "**", with: "^")
        // "3x4" multiplies; "x" elsewhere isn't math.
        s = s.replacingOccurrences(of: #"(?<=\d)\s*x\s*(?=[\d(])"#, with: "*", options: .regularExpression)
        // Decimal commas where the Mac uses them ("3,5 + 1"); thousands separators elsewhere.
        if decimalSeparator == "," {
            s = s.replacingOccurrences(of: #"(?<=\d),(?=\d)"#, with: ".", options: .regularExpression)
        } else {
            s = s.replacingOccurrences(of: #"(?<=\d),(?=\d{3}\b)"#, with: "", options: .regularExpression)
        }
        // "15% of 240" and "20% off 80".
        s = s.replacingOccurrences(of: #"([\d.]+)\s*%\s*off\s*([\d.]+)"#, with: "$2*(1-$1/100)", options: .regularExpression)
        s = s.replacingOccurrences(of: #"([\d.]+)\s*%\s*of\b\s*"#, with: "($1/100)*", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\bmod\b"#, with: "#", options: .regularExpression)
        return s
    }

    // MARK: - Tokens

    enum Token: Equatable {
        case number(Double)
        case op(Character)
        case open, close
        case name(String)
    }

    static func tokenize(_ s: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == " " { i += 1; continue }
            if c.isNumber || c == "." {
                var j = i
                while j < chars.count, chars[j].isNumber || chars[j] == "." { j += 1 }
                // Scientific notation: "1e6".
                if j < chars.count, chars[j] == "e", j + 1 < chars.count, chars[j + 1].isNumber || chars[j + 1] == "-" {
                    var k = j + 1
                    if chars[k] == "-" { k += 1 }
                    while k < chars.count, chars[k].isNumber { k += 1 }
                    j = k
                }
                guard let value = Double(String(chars[i..<j])) else { return [] }
                tokens.append(.number(value))
                i = j
            } else if c.isLetter {
                var j = i
                while j < chars.count, chars[j].isLetter || chars[j].isNumber { j += 1 }
                tokens.append(.name(String(chars[i..<j])))
                i = j
            } else if "+-*/^%!#".contains(c) {
                tokens.append(.op(c))
                i += 1
            } else if c == "(" {
                tokens.append(.open); i += 1
            } else if c == ")" {
                tokens.append(.close); i += 1
            } else {
                return []
            }
        }
        return tokens
    }

    // MARK: - Parsing

    struct Parser {
        let tokens: [Token]
        var index = 0
        /// Some operation was actually performed (a bare "42" isn't a calculation).
        var didWork = false

        init(tokens: [Token]) { self.tokens = tokens }

        var atEnd: Bool { index == tokens.count }
        private var current: Token? { index < tokens.count ? tokens[index] : nil }

        mutating func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while case .op(let op) = current, op == "+" || op == "-" {
                index += 1
                guard let rhs = parseTerm() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
                didWork = true
            }
            return value
        }

        mutating func parseTerm() -> Double? {
            guard var value = parsePower() else { return nil }
            while true {
                if case .op(let op) = current, op == "*" || op == "/" || op == "#" {
                    index += 1
                    guard let rhs = parsePower() else { return nil }
                    switch op {
                    case "*": value *= rhs
                    case "/": guard rhs != 0 else { return nil }; value /= rhs
                    default: guard rhs != 0 else { return nil }; value = value.truncatingRemainder(dividingBy: rhs)
                    }
                    didWork = true
                } else if case .open = current {
                    // "2(3+4)" multiplies.
                    guard let rhs = parsePower() else { return nil }
                    value *= rhs
                    didWork = true
                } else {
                    return value
                }
            }
        }

        mutating func parsePower() -> Double? {
            guard let base = parseUnary() else { return nil }
            if case .op("^") = current {
                index += 1
                guard let exponent = parsePower() else { return nil }
                didWork = true
                return pow(base, exponent)
            }
            return base
        }

        mutating func parseUnary() -> Double? {
            if case .op(let op) = current, op == "-" || op == "+" {
                index += 1
                guard let value = parseUnary() else { return nil }
                return op == "-" ? -value : value
            }
            return parsePostfix()
        }

        mutating func parsePostfix() -> Double? {
            guard var value = parsePrimary() else { return nil }
            while case .op(let op) = current, op == "%" || op == "!" {
                index += 1
                didWork = true
                if op == "%" {
                    value /= 100
                } else {
                    guard value >= 0, value <= 170, value == value.rounded() else { return nil }
                    value = (1...max(1, Int(value))).reduce(1.0) { $0 * Double($1) }
                }
            }
            return value
        }

        mutating func parsePrimary() -> Double? {
            switch current {
            case .number(let value):
                index += 1
                return value
            case .open:
                index += 1
                guard let value = parseExpression(), case .close = current else { return nil }
                index += 1
                return value
            case .name(let name):
                index += 1
                if let constant = Self.constants[name] { return constant }
                guard let function = Self.functions[name] else { return nil }
                // "sqrt 2" and "sqrt(2)" both work.
                guard let argument = parsePower() else { return nil }
                didWork = true
                let value = function(argument)
                return value.isFinite ? value : nil
            default:
                return nil
            }
        }

        static let constants: [String: Double] = ["pi": .pi, "e": M_E, "tau": 2 * .pi]
        static let functions: [String: (Double) -> Double] = [
            "sqrt": { sqrt($0) }, "cbrt": { cbrt($0) }, "abs": { abs($0) },
            "sin": { sin($0) }, "cos": { cos($0) }, "tan": { tan($0) },
            "asin": { asin($0) }, "acos": { acos($0) }, "atan": { atan($0) },
            "ln": { log($0) }, "log": { log10($0) }, "log2": { log2($0) }, "exp": { exp($0) },
            "round": { $0.rounded() }, "floor": { floor($0) }, "ceil": { ceil($0) },
        ]
    }

    // MARK: - Showing numbers

    /// A result the way a calculator shows it: up to 12 significant digits, the Mac's own number
    /// format, scientific notation only when it must.
    static func format(_ value: Double, locale: Locale = .current) -> String {
        if value == 0 { return "0" }
        let magnitude = abs(value)
        if magnitude >= 1e15 || magnitude < 1e-9 {
            return value.formatted(.number.notation(.scientific).precision(.significantDigits(1...10)).locale(locale))
        }
        return value.formatted(.number.precision(.significantDigits(1...12)).locale(locale))
    }
}
