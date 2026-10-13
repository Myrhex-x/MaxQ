//
//  QuickAnswer.swift
//  Max Q
//
//  Answers Max Q gives on its own, at the top of the results page, without Grok and without a key:
//  a calculation, a unit or currency conversion, the time somewhere, the weather. Searches like
//  these don't ask Grok on their own, since the answer is already there (and costs nothing).
//
//  Calculations, units and times are worked out on this Mac. Currency rates come from Frankfurter
//  (the European Central Bank's daily reference rates) and weather from Open-Meteo, asked only for
//  a search that needs them.
//

import Foundation

nonisolated enum QuickAnswerRequest: Equatable {
    case calculation(expression: String, value: Double)
    case conversion(UnitConversion)
    case currency(amount: Double, from: String, to: String)
    case time(city: String, zone: TimeZone)
    case weather(place: String?)

    /// What a search asks for, if it's one Max Q answers itself.
    static func detect(_ query: String) -> QuickAnswerRequest? {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 120 else { return nil }
        if let currency = CurrencyQuery.parse(text) {
            return .currency(amount: currency.amount, from: currency.from, to: currency.to)
        }
        if let conversion = UnitConversion.parse(text) { return .conversion(conversion) }
        if let time = TimeQuery.parse(text) { return .time(city: time.city, zone: time.zone) }
        if let place = WeatherQuery.parse(text) { return .weather(place: place.isEmpty ? nil : place) }
        if let value = Calculator.evaluate(text) { return .calculation(expression: text, value: value) }
        return nil
    }
}

// MARK: - Currency

nonisolated enum CurrencyQuery {
    /// Currencies the European Central Bank publishes a daily rate for.
    static let codes: Set<String> = [
        "AUD", "BGN", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "EUR", "GBP", "HKD", "HUF", "IDR", "ILS", "INR",
        "ISK", "JPY", "KRW", "MXN", "MYR", "NOK", "NZD", "PHP", "PLN", "RON", "SEK", "SGD", "THB", "TRY", "USD", "ZAR",
    ]

    private static let names: [String: String] = [
        "$": "USD", "us$": "USD", "dollar": "USD", "dollars": "USD", "usd": "USD", "bucks": "USD",
        "€": "EUR", "euro": "EUR", "euros": "EUR",
        "£": "GBP", "pound": "GBP", "pounds": "GBP", "quid": "GBP", "sterling": "GBP",
        "¥": "JPY", "yen": "JPY", "₹": "INR", "rupee": "INR", "rupees": "INR", "₩": "KRW", "won": "KRW",
        "₺": "TRY", "lira": "TRY", "fr": "CHF", "franc": "CHF", "francs": "CHF", "swiss franc": "CHF",
        "yuan": "CNY", "rmb": "CNY", "real": "BRL", "reais": "BRL", "peso": "MXN", "pesos": "MXN",
        "c$": "CAD", "a$": "AUD", "zloty": "PLN", "złoty": "PLN", "krona": "SEK", "kronor": "SEK", "krone": "NOK",
        "rand": "ZAR", "shekel": "ILS", "shekels": "ILS", "baht": "THB", "forint": "HUF",
    ]

    static func code(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if codes.contains(name.uppercased()) { return name.uppercased() }
        return names[name]
    }

    /// "100 usd to eur", "€50 in dollars", "20 pounds in euros".
    static func parse(_ text: String, decimalSeparator: String = Locale.current.decimalSeparator ?? ".") -> (amount: Double, from: String, to: String)? {
        let lower = text.lowercased()
        let pattern = #"^(?:convert\s+)?([^\d\s-]{0,3})\s*(-?[\d.,]+)\s*([a-z$€£¥₹₩₺ ]{0,14}?)\s+(?:in|to|into|en|=|->|→)\s+([a-z$€£¥₹₩₺ ]{1,14})\??$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              let prefixRange = Range(match.range(at: 1), in: lower),
              let numberRange = Range(match.range(at: 2), in: lower),
              let fromRange = Range(match.range(at: 3), in: lower),
              let toRange = Range(match.range(at: 4), in: lower) else { return nil }
        let fromText = String(lower[fromRange]).isEmpty ? String(lower[prefixRange]) : String(lower[fromRange])
        guard let from = code(fromText), let to = code(String(lower[toRange])), from != to else { return nil }
        var number = String(lower[numberRange])
        number = decimalSeparator == "," ? number.replacingOccurrences(of: ",", with: ".") : number.replacingOccurrences(of: ",", with: "")
        guard let amount = Double(number), amount >= 0 else { return nil }
        return (amount, from, to)
    }
}

/// Daily reference rates from the European Central Bank, through Frankfurter (no key, no account).
nonisolated enum CurrencyClient {
    struct Rate: Equatable {
        let amount: Double
        let result: Double
        /// The day the rate was published.
        let date: String
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()

    static func convert(_ amount: Double, from: String, to: String) async throws -> Rate {
        var components = URLComponents(string: "https://api.frankfurter.dev/v1/latest")!
        components.queryItems = [
            URLQueryItem(name: "amount", value: String(amount)),
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
        ]
        let (data, response) = try await session.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rates = json["rates"] as? [String: Any],
              let result = (rates[to] as? Double) ?? (rates[to] as? Int).map(Double.init) else {
            throw URLError(.badServerResponse)
        }
        return Rate(amount: amount, result: result, date: json["date"] as? String ?? "")
    }
}

// MARK: - Time

nonisolated enum TimeQuery {
    /// "time in tokyo", "tokyo time", "what time is it in new york", "heure à paris".
    static func parse(_ text: String) -> (city: String, zone: TimeZone)? {
        let lower = text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " ?"))
        let patterns = [
            #"^(?:what(?:'s| is)? the )?(?:current )?time (?:is it )?(?:in|at) (.+)$"#,
            #"^what time is it (?:in|at) (.+)$"#,
            #"^time (?:in |at )?(.+)$"#,
            #"^(.+?) time(?: now)?$"#,
            #"^(?:quelle )?heure (?:est-il )?(?:à|a|en|au) (.+)$"#,
            #"^heure (.+)$"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
                  let range = Range(match.range(at: 1), in: lower) else { continue }
            let place = String(lower[range]).trimmingCharacters(in: .whitespaces)
            if let zone = zone(for: place) { return (title(for: place), zone) }
        }
        return nil
    }

    /// The time zone of a city, a country or a zone's own name ("pst", "utc").
    static func zone(for place: String) -> TimeZone? {
        let key = place.lowercased().trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        if let id = aliases[key], let zone = TimeZone(identifier: id) { return zone }
        if let id = cities[key], let zone = TimeZone(identifier: id) { return zone }
        if abbreviations.contains(key), let zone = TimeZone(abbreviation: key.uppercased()) { return zone }
        return nil
    }

    /// Zone names people type ("pst"), not every three letters TimeZone knows ("cat").
    private static let abbreviations: Set<String> = [
        "utc", "gmt", "pst", "pdt", "mst", "mdt", "cst", "cdt", "est", "edt", "akst", "hst", "cet", "cest",
        "bst", "wet", "west", "eet", "eest", "msk", "ist", "jst", "kst", "hkt", "sgt", "aest", "aedt", "nzst", "nzdt",
    ]

    /// "new york" → "New York", "pst" → "PST".
    static func title(for place: String) -> String {
        let trimmed = place.trimmingCharacters(in: .whitespaces)
        if trimmed.count <= 4, aliases[trimmed.lowercased()] == nil, cities[trimmed.lowercased()] == nil { return trimmed.uppercased() }
        return trimmed.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// Every city in the system's time zone list, by its name ("los angeles": "America/Los_Angeles").
    private static let cities: [String: String] = {
        var table: [String: String] = [:]
        for id in TimeZone.knownTimeZoneIdentifiers {
            guard let city = id.split(separator: "/").last else { continue }
            table[city.replacingOccurrences(of: "_", with: " ").lowercased()] = id
        }
        return table
    }()

    private static let aliases: [String: String] = [
        "nyc": "America/New_York", "new york city": "America/New_York", "boston": "America/New_York",
        "washington": "America/New_York", "washington dc": "America/New_York", "miami": "America/New_York",
        "atlanta": "America/New_York", "philadelphia": "America/New_York", "toronto": "America/Toronto",
        "montreal": "America/Toronto", "montréal": "America/Toronto", "chicago": "America/Chicago",
        "dallas": "America/Chicago", "houston": "America/Chicago", "austin": "America/Chicago", "texas": "America/Chicago",
        "denver": "America/Denver", "la": "America/Los_Angeles", "san francisco": "America/Los_Angeles",
        "sf": "America/Los_Angeles", "seattle": "America/Los_Angeles", "california": "America/Los_Angeles",
        "silicon valley": "America/Los_Angeles", "san diego": "America/Los_Angeles", "las vegas": "America/Los_Angeles",
        "hawaii": "Pacific/Honolulu", "mexico": "America/Mexico_City", "brazil": "America/Sao_Paulo",
        "rio": "America/Sao_Paulo", "rio de janeiro": "America/Sao_Paulo", "são paulo": "America/Sao_Paulo",
        "uk": "Europe/London", "england": "Europe/London", "united kingdom": "Europe/London", "britain": "Europe/London",
        "france": "Europe/Paris", "germany": "Europe/Berlin", "allemagne": "Europe/Berlin", "spain": "Europe/Madrid",
        "espagne": "Europe/Madrid", "italy": "Europe/Rome", "italie": "Europe/Rome", "milan": "Europe/Rome",
        "netherlands": "Europe/Amsterdam", "belgium": "Europe/Brussels", "switzerland": "Europe/Zurich",
        "geneva": "Europe/Zurich", "genève": "Europe/Zurich", "portugal": "Europe/Lisbon", "ireland": "Europe/Dublin",
        "poland": "Europe/Warsaw", "sweden": "Europe/Stockholm", "norway": "Europe/Oslo", "denmark": "Europe/Copenhagen",
        "finland": "Europe/Helsinki", "greece": "Europe/Athens", "turkey": "Europe/Istanbul", "russia": "Europe/Moscow",
        "kyiv": "Europe/Kyiv", "kiev": "Europe/Kyiv", "ukraine": "Europe/Kyiv", "egypt": "Africa/Cairo",
        "nigeria": "Africa/Lagos", "kenya": "Africa/Nairobi", "south africa": "Africa/Johannesburg",
        "cape town": "Africa/Johannesburg", "dubai": "Asia/Dubai", "abu dhabi": "Asia/Dubai", "uae": "Asia/Dubai",
        "israel": "Asia/Jerusalem", "tel aviv": "Asia/Jerusalem", "saudi arabia": "Asia/Riyadh", "india": "Asia/Kolkata",
        "delhi": "Asia/Kolkata", "new delhi": "Asia/Kolkata", "mumbai": "Asia/Kolkata", "bangalore": "Asia/Kolkata",
        "bengaluru": "Asia/Kolkata", "china": "Asia/Shanghai", "beijing": "Asia/Shanghai", "shenzhen": "Asia/Shanghai",
        "japan": "Asia/Tokyo", "japon": "Asia/Tokyo", "osaka": "Asia/Tokyo", "kyoto": "Asia/Tokyo",
        "korea": "Asia/Seoul", "south korea": "Asia/Seoul", "taiwan": "Asia/Taipei", "thailand": "Asia/Bangkok",
        "vietnam": "Asia/Ho_Chi_Minh", "indonesia": "Asia/Jakarta", "bali": "Asia/Makassar", "philippines": "Asia/Manila",
        "australia": "Australia/Sydney", "new zealand": "Pacific/Auckland", "starbase": "America/Chicago",
    ]
}

// MARK: - Weather

nonisolated enum WeatherQuery {
    /// The place a weather search asks about: "weather in tokyo" → "tokyo"; "weather" alone → ""
    /// (where this Mac is, from its time zone).
    static func parse(_ text: String) -> String? {
        let lower = text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " ?"))
        let patterns = [
            #"^(?:the )?(?:weather|forecast|temperature)(?: (?:today|now|tomorrow|this week))?(?: (?:in|at|for) (.+))?$"#,
            #"^(.+?) (?:weather|forecast)(?: (?:today|now|tomorrow|this week))?$"#,
            #"^(?:météo|meteo)(?: (?:à|a|en|au|de|pour))?(?: (.+))?$"#,
            #"^(?:what's|what is|how's|how is) the weather(?: like)?(?: (?:in|at) (.+))?$"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) else { continue }
            if match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: lower) {
                let place = String(lower[range]).trimmingCharacters(in: .whitespaces)
                guard place.count <= 60, !place.contains(where: \.isNumber) else { return nil }
                // "forecast for tomorrow" is about when, not where.
                return ["today", "tomorrow", "now", "this week", "tonight"].contains(place) ? "" : place
            }
            return ""
        }
        return nil
    }

    /// Where this Mac is, near enough for the weather: the city of its time zone ("Europe/Paris").
    static var localPlace: String? {
        guard let city = TimeZone.current.identifier.split(separator: "/").last else { return nil }
        let name = city.replacingOccurrences(of: "_", with: " ")
        return name == "UTC" || name == "GMT" ? nil : name
    }
}
