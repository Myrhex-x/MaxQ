//
//  WeatherClient.swift
//  Max Q
//
//  The weather for a place, from Open-Meteo (free, no key, no account; data CC BY 4.0): its
//  geocoder finds the place, its forecast gives now and the next five days. Asked only for a
//  weather search, with nothing but the place's name and then its coordinates.
//

import Foundation

nonisolated struct WeatherReport: Equatable, Sendable {
    struct Day: Equatable, Sendable, Identifiable {
        var id: String { date }
        let date: String
        let code: Int
        let high: Double
        let low: Double
        /// Chance of rain or snow, in percent.
        let precipitation: Int?
    }

    let place: String
    /// "Île-de-France, France".
    let region: String
    let temperature: Double
    let feelsLike: Double
    let humidity: Int
    let wind: Double
    let code: Int
    let isDay: Bool
    let fahrenheit: Bool
    let days: [Day]

    var temperatureUnit: String { fahrenheit ? "°F" : "°C" }
    var windUnit: String { fahrenheit ? "mph" : "km/h" }
}

/// What the WMO weather codes Open-Meteo reports look like, in words and in a glyph.
nonisolated enum WeatherCondition {
    static func label(_ code: Int) -> String {
        switch code {
        case 0: String(localized: "weather.clear", defaultValue: "Clear", comment: "A clear sky")
        case 1: String(localized: "Mostly clear")
        case 2: String(localized: "Partly cloudy")
        case 3: String(localized: "Overcast")
        case 45, 48: String(localized: "Fog")
        case 51, 53, 55: String(localized: "Drizzle")
        case 56, 57: String(localized: "Freezing drizzle")
        case 61: String(localized: "Light rain")
        case 63: String(localized: "Rain")
        case 65: String(localized: "Heavy rain")
        case 66, 67: String(localized: "Freezing rain")
        case 71: String(localized: "Light snow")
        case 73: String(localized: "Snow")
        case 75: String(localized: "Heavy snow")
        case 77: String(localized: "Snow grains")
        case 80, 81: String(localized: "Showers")
        case 82: String(localized: "Heavy showers")
        case 85, 86: String(localized: "Snow showers")
        case 95: String(localized: "Thunderstorm")
        case 96, 99: String(localized: "Thunderstorm with hail")
        default: String(localized: "Unknown")
        }
    }

    static func icon(_ code: Int, isDay: Bool = true) -> MQIcon {
        switch code {
        case 0: isDay ? .sun : .moon
        case 1, 2: isDay ? .cloudSun : .cloudMoon
        case 3: .cloud
        case 45, 48: .fog
        case 51, 53, 55, 56, 57: .drizzle
        case 61, 63, 65, 66, 67, 80, 81, 82: .rain
        case 71, 73, 75, 77, 85, 86: .snow
        case 95, 96, 99: .storm
        default: .cloud
        }
    }
}

nonisolated enum WeatherClient {
    enum Failure: LocalizedError {
        case noPlace(String)
        var errorDescription: String? {
            switch self {
            case .noPlace(let place): String(localized: "Max Q couldn't find a place called “\(place)”.")
            }
        }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()

    static func report(for place: String, fahrenheit: Bool, language: String) async throws -> WeatherReport {
        var geo = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        geo.queryItems = [
            URLQueryItem(name: "name", value: String(place.prefix(60))),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "format", value: "json"),
        ]
        let (geoData, _) = try await session.data(from: geo.url!)
        guard let geoJSON = try JSONSerialization.jsonObject(with: geoData) as? [String: Any],
              let first = (geoJSON["results"] as? [[String: Any]])?.first,
              let latitude = first["latitude"] as? Double, let longitude = first["longitude"] as? Double else {
            throw Failure.noPlace(place)
        }
        let name = first["name"] as? String ?? place
        let region = [first["admin1"] as? String, first["country"] as? String]
            .compactMap { $0 }.filter { !$0.isEmpty && $0 != name }.joined(separator: ", ")

        var forecast = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        forecast.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "5"),
            URLQueryItem(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
            URLQueryItem(name: "wind_speed_unit", value: fahrenheit ? "mph" : "kmh"),
        ]
        let (data, response) = try await session.data(from: forecast.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try parse(data, place: name, region: region, fahrenheit: fahrenheit)
    }

    static func parse(_ data: Data, place: String, region: String, fahrenheit: Bool) throws -> WeatherReport {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = json["current"] as? [String: Any],
              let daily = json["daily"] as? [String: Any] else { throw URLError(.cannotParseResponse) }
        func number(_ value: Any?) -> Double { (value as? Double) ?? (value as? Int).map(Double.init) ?? 0 }
        let dates = daily["time"] as? [String] ?? []
        let codes = daily["weather_code"] as? [Any] ?? []
        let highs = daily["temperature_2m_max"] as? [Any] ?? []
        let lows = daily["temperature_2m_min"] as? [Any] ?? []
        let rain = daily["precipitation_probability_max"] as? [Any] ?? []
        let days = dates.indices.map { index in
            WeatherReport.Day(date: dates[index],
                              code: Int(number(codes.indices.contains(index) ? codes[index] : nil)),
                              high: number(highs.indices.contains(index) ? highs[index] : nil),
                              low: number(lows.indices.contains(index) ? lows[index] : nil),
                              precipitation: rain.indices.contains(index) ? (rain[index] as? Int ?? (rain[index] as? Double).map { Int($0) }) : nil)
        }
        return WeatherReport(place: place, region: region,
                             temperature: number(current["temperature_2m"]),
                             feelsLike: number(current["apparent_temperature"]),
                             humidity: Int(number(current["relative_humidity_2m"])),
                             wind: number(current["wind_speed_10m"]),
                             code: Int(number(current["weather_code"])),
                             isDay: number(current["is_day"]) != 0,
                             fahrenheit: fahrenheit, days: days)
    }
}
