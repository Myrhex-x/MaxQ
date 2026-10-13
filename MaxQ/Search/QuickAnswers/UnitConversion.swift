//
//  UnitConversion.swift
//  Max Q
//
//  "10 km in miles", "70 kg to lb", "350 f in c", "2 cups in ml", "1 tb in gb": converted on this
//  Mac with Foundation's own units. Pure logic, unit-tested.
//

import Foundation

nonisolated struct UnitConversion: Equatable {
    let value: Double
    let from: Dimension
    let to: Dimension
    /// What the user typed for each unit, as they typed it.
    let fromName: String
    let toName: String

    var result: Double {
        Measurement(value: value, unit: from).converted(to: to).value
    }

    /// The same conversion the other way round, starting from the result.
    var reversed: UnitConversion {
        UnitConversion(value: result, from: to, to: from, fromName: toName, toName: fromName)
    }

    static func == (lhs: UnitConversion, rhs: UnitConversion) -> Bool {
        lhs.value == rhs.value && lhs.from == rhs.from && lhs.to == rhs.to
    }

    /// "10 km in miles" and friends. Both units must measure the same thing.
    static func parse(_ text: String, decimalSeparator: String = Locale.current.decimalSeparator ?? ".") -> UnitConversion? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(?:convert\s+)?(-?[\d.,]+)\s*([^\d\s][^=]*?)\s+(?:in|to|into|as|en|=|->|→)\s+([^\d].*?)\??$"#
        guard let match = lower.range(of: pattern, options: .regularExpression) else { return nil }
        let line = String(lower[match])
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let found = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let numberRange = Range(found.range(at: 1), in: line),
              let fromRange = Range(found.range(at: 2), in: line),
              let toRange = Range(found.range(at: 3), in: line) else { return nil }
        var number = String(line[numberRange])
        number = decimalSeparator == "," ? number.replacingOccurrences(of: ",", with: ".") : number.replacingOccurrences(of: ",", with: "")
        guard let value = Double(number) else { return nil }
        let fromName = String(line[fromRange]).trimmingCharacters(in: .whitespaces)
        let toName = String(line[toRange]).trimmingCharacters(in: .whitespaces)
        guard let from = unit(named: fromName), let to = unit(named: toName),
              type(of: from) == type(of: to), from != to else { return nil }
        return UnitConversion(value: value, from: from, to: to, fromName: fromName, toName: toName)
    }

    static func unit(named raw: String) -> Dimension? {
        var name = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        if let exact = units[name] { return exact }
        // Plurals: "miles", "inches", "feet" is in the table.
        if name.hasSuffix("es"), let unit = units[String(name.dropLast(2))] { return unit }
        if name.hasSuffix("s") {
            name.removeLast()
            return units[name]
        }
        return nil
    }

    private static let day = UnitDuration(symbol: "d", converter: UnitConverterLinear(coefficient: 86_400))
    private static let week = UnitDuration(symbol: "wk", converter: UnitConverterLinear(coefficient: 604_800))
    private static let year = UnitDuration(symbol: "yr", converter: UnitConverterLinear(coefficient: 31_557_600))

    static let units: [String: Dimension] = {
        var table: [String: Dimension] = [:]
        func add(_ unit: Dimension, _ names: String...) { for name in names { table[name] = unit } }
        // Length
        add(UnitLength.millimeters, "mm", "millimeter", "millimetre")
        add(UnitLength.centimeters, "cm", "centimeter", "centimetre")
        add(UnitLength.meters, "m", "meter", "metre", "mètre")
        add(UnitLength.kilometers, "km", "kilometer", "kilometre", "kilomètre", "kms")
        add(UnitLength.inches, "in", "inch", "\"", "pouce")
        add(UnitLength.feet, "ft", "foot", "feet", "'", "pied")
        add(UnitLength.yards, "yd", "yard")
        add(UnitLength.miles, "mi", "mile")
        add(UnitLength.nauticalMiles, "nmi", "nautical mile")
        add(UnitLength.lightyears, "ly", "light year", "lightyear")
        // Mass
        add(UnitMass.milligrams, "mg", "milligram", "milligramme")
        add(UnitMass.grams, "g", "gram", "gramme", "gr")
        add(UnitMass.kilograms, "kg", "kilogram", "kilogramme", "kilo", "kgs")
        add(UnitMass.metricTons, "t", "tonne", "metric ton", "ton")
        add(UnitMass.ounces, "oz", "ounce", "once")
        add(UnitMass.pounds, "lb", "lbs", "pound", "livre")
        add(UnitMass.stones, "st", "stone")
        // Temperature
        add(UnitTemperature.celsius, "c", "°c", "celsius", "degrees celsius", "degree celsius", "°")
        add(UnitTemperature.fahrenheit, "f", "°f", "fahrenheit", "degrees fahrenheit", "degree fahrenheit")
        add(UnitTemperature.kelvin, "k", "kelvin")
        // Volume
        add(UnitVolume.milliliters, "ml", "milliliter", "millilitre")
        add(UnitVolume.centiliters, "cl", "centiliter", "centilitre")
        add(UnitVolume.liters, "l", "liter", "litre")
        add(UnitVolume.cubicMeters, "m3", "m³", "cubic meter", "cubic metre")
        add(UnitVolume.teaspoons, "tsp", "teaspoon")
        add(UnitVolume.tablespoons, "tbsp", "tablespoon")
        add(UnitVolume.cups, "cup")
        add(UnitVolume.fluidOunces, "fl oz", "floz", "fluid ounce")
        add(UnitVolume.pints, "pt", "pint")
        add(UnitVolume.quarts, "qt", "quart")
        add(UnitVolume.gallons, "gal", "gallon")
        // Speed
        add(UnitSpeed.kilometersPerHour, "km/h", "kmh", "kph", "kmph", "kilometers per hour", "kilometres per hour")
        add(UnitSpeed.milesPerHour, "mph", "miles per hour")
        add(UnitSpeed.metersPerSecond, "m/s", "meters per second", "metres per second")
        add(UnitSpeed.knots, "kn", "knot", "kt")
        // Area
        add(UnitArea.squareMeters, "m2", "m²", "sq m", "square meter", "square metre", "sqm")
        add(UnitArea.squareKilometers, "km2", "km²", "sq km", "square kilometer", "square kilometre")
        add(UnitArea.squareFeet, "ft2", "ft²", "sq ft", "square foot", "square feet", "sqft")
        add(UnitArea.squareMiles, "mi2", "mi²", "sq mi", "square mile")
        add(UnitArea.hectares, "ha", "hectare")
        add(UnitArea.acres, "ac", "acre")
        // Time
        add(UnitDuration.seconds, "s", "sec", "second", "seconde")
        add(UnitDuration.minutes, "min", "minute", "mins")
        add(UnitDuration.hours, "h", "hr", "hour", "heure", "hrs")
        add(day, "d", "day", "jour")
        add(week, "wk", "week", "semaine")
        add(year, "yr", "year", "an", "année")
        // Data (decimal, as storage is sold; KiB and friends for binary)
        add(UnitInformationStorage.bits, "bit")
        add(UnitInformationStorage.bytes, "b", "byte", "octet", "o")
        add(UnitInformationStorage.kilobytes, "kb", "kilobyte", "ko")
        add(UnitInformationStorage.megabytes, "mb", "megabyte", "mo")
        add(UnitInformationStorage.gigabytes, "gb", "gigabyte", "go")
        add(UnitInformationStorage.terabytes, "tb", "terabyte", "to")
        add(UnitInformationStorage.kibibytes, "kib", "kibibyte")
        add(UnitInformationStorage.mebibytes, "mib", "mebibyte")
        add(UnitInformationStorage.gibibytes, "gib", "gibibyte")
        // Energy
        add(UnitEnergy.joules, "j", "joule")
        add(UnitEnergy.kilojoules, "kj", "kilojoule")
        add(UnitEnergy.kilocalories, "kcal", "calorie", "cal", "kilocalorie")
        add(UnitEnergy.kilowattHours, "kwh", "kilowatt hour")
        // Angle
        add(UnitAngle.degrees, "deg", "degree", "degré")
        add(UnitAngle.radians, "rad", "radian")
        return table
    }()

    /// A unit named for reading: "miles", "kilograms", "°F".
    static func name(of unit: Dimension, value: Double) -> String {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = unit is UnitTemperature ? .short : .long
        let string = formatter.string(from: Measurement(value: value, unit: unit))
        // The formatter writes the number too; keep only the unit's name.
        let number = formatter.numberFormatter.string(from: NSNumber(value: value)) ?? ""
        return string.replacingOccurrences(of: number, with: "").trimmingCharacters(in: .whitespaces)
    }
}
