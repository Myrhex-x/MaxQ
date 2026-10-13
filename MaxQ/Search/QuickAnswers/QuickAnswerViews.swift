//
//  QuickAnswerViews.swift
//  Max Q
//
//  The answers Max Q gives itself, at the top of the results page and in the page's own manner:
//  no card, the question in a quiet line, the answer in large figures that roll when they change,
//  and a hairline before the rest. A conversion turns round with one click; the time ticks; the
//  weather shows now and the next five days.
//

import AppKit
import SwiftUI

struct QuickAnswerView: View {
    let search: GrokSearch
    @State private var revealed = false

    var body: some View {
        if let quick = search.quick {
            VStack(alignment: .leading, spacing: 0) {
                switch quick {
                case let .calculation(expression, value):
                    CalculationAnswer(expression: expression, value: value, revealed: revealed)
                case .conversion(let conversion):
                    ConversionAnswer(conversion: conversion, revealed: revealed)
                case let .currency(amount, from, to):
                    CurrencyAnswer(amount: amount, from: from, to: to, rate: search.quickRate,
                                   failure: search.quickFailure, revealed: revealed)
                case let .time(city, zone):
                    TimeAnswer(city: city, zone: zone, revealed: revealed)
                case .weather:
                    WeatherAnswer(report: search.quickWeather, failure: search.quickFailure)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 26)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            .padding(.bottom, 24)
            .onAppear { revealed = true }
        }
    }
}

// MARK: - Pieces

/// The question, in a quiet line above the answer.
private struct QuestionLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(2)
            .contentTransition(.numericText())
    }
}

/// The answer in large figures, x.ai's headline weight with its tight tracking.
private struct Figure: View {
    let text: String
    var size: CGFloat = 46

    var body: some View {
        Text(text)
            .font(.hero(size))
            .tracking(-size * 0.02)
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .contentTransition(.numericText())
            .textSelection(.enabled)
    }
}

/// Where a looked-up answer came from, at the foot.
private struct SourceLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.textTertiary)
    }
}

private struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
        } label: {
            ZStack {
                if copied { Icon(.check, size: 16).transition(.glyphSwap) } else { Icon(.copy, size: 16).transition(.glyphSwap) }
            }
            .animation(Motion.spring(0.2), value: copied)
        }
        .iconButton(size: 32)
        .tip(copied ? "Copied" : "Copy")
        .accessibilityLabel("Copy")
    }
}

/// Turns a conversion round: two arrows pointing opposite ways, which spin a half turn.
private struct SwapButton: View {
    let action: () -> Void
    @State private var turns = 0.0

    var body: some View {
        Button {
            withAnimation(Motion.spring(0.5)) { turns += 180 }
            action()
        } label: {
            Icon(.chevronUpDown, size: 17)
                .rotationEffect(.degrees(90 + turns))
        }
        .iconButton(size: 32)
        .tip("Swap")
        .accessibilityLabel("Swap")
    }
}

// MARK: - Calculation

private struct CalculationAnswer: View {
    let expression: String
    let value: Double
    let revealed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            QuestionLine(text: Calculator.display(expression) + " =")
                .reveal(revealed)
            HStack(alignment: .firstTextBaseline) {
                Figure(text: Calculator.format(value))
                Spacer(minLength: 12)
                CopyButton(text: Calculator.format(value, locale: Locale(identifier: "en_US_POSIX")))
            }
            .reveal(revealed, delay: 0.05)
        }
    }
}

// MARK: - Units

private struct ConversionAnswer: View {
    let conversion: UnitConversion
    let revealed: Bool
    @State private var flipped = false

    private var shown: UnitConversion { flipped ? conversion.reversed : conversion }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            QuestionLine(text: "\(Self.number(shown.value)) \(UnitConversion.name(of: shown.from, value: shown.value)) =")
                .reveal(revealed)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Figure(text: Self.number(shown.result))
                Text(UnitConversion.name(of: shown.to, value: shown.result))
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.textSecondary)
                    .contentTransition(.interpolate)
                Spacer(minLength: 12)
                SwapButton { withAnimation(Motion.spring(0.45)) { flipped.toggle() } }
                CopyButton(text: Self.number(shown.result))
            }
            .reveal(revealed, delay: 0.05)
            if !others.isEmpty {
                Text(others.joined(separator: "   ·   "))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
                    .contentTransition(.numericText())
                    .padding(.top, 6)
                    .reveal(revealed, delay: 0.1)
            }
        }
    }

    /// The same amount in a few other units people use for this kind of measure.
    private var others: [String] {
        let measurement = Measurement(value: shown.value, unit: shown.from)
        return Self.related(to: shown.from)
            .filter { $0 != shown.from && $0 != shown.to }
            .prefix(3)
            .map { unit in
                let value = measurement.converted(to: unit).value
                return "\(Self.number(value)) \(UnitConversion.name(of: unit, value: value))"
            }
    }

    static func related(to unit: Dimension) -> [Dimension] {
        switch unit {
        case is UnitLength: [UnitLength.meters, UnitLength.kilometers, UnitLength.miles, UnitLength.feet, UnitLength.inches, UnitLength.centimeters]
        case is UnitMass: [UnitMass.kilograms, UnitMass.pounds, UnitMass.grams, UnitMass.ounces]
        case is UnitTemperature: [UnitTemperature.celsius, UnitTemperature.fahrenheit, UnitTemperature.kelvin]
        case is UnitVolume: [UnitVolume.liters, UnitVolume.milliliters, UnitVolume.cups, UnitVolume.gallons, UnitVolume.fluidOunces]
        case is UnitSpeed: [UnitSpeed.kilometersPerHour, UnitSpeed.milesPerHour, UnitSpeed.metersPerSecond, UnitSpeed.knots]
        case is UnitArea: [UnitArea.squareMeters, UnitArea.squareFeet, UnitArea.hectares, UnitArea.acres]
        case is UnitDuration: [UnitDuration.seconds, UnitDuration.minutes, UnitDuration.hours]
        case is UnitInformationStorage: [UnitInformationStorage.megabytes, UnitInformationStorage.gigabytes, UnitInformationStorage.terabytes, UnitInformationStorage.gibibytes]
        case is UnitEnergy: [UnitEnergy.kilocalories, UnitEnergy.kilojoules, UnitEnergy.kilowattHours]
        default: []
        }
    }

    static func number(_ value: Double) -> String {
        if value != 0, abs(value) < 0.0001 || abs(value) >= 1e12 {
            return value.formatted(.number.notation(.scientific).precision(.significantDigits(1...4)))
        }
        return value.formatted(.number.precision(.significantDigits(1...6)))
    }
}

// MARK: - Currency

private struct CurrencyAnswer: View {
    let amount: Double
    let from: String
    let to: String
    let rate: CurrencyClient.Rate?
    let failure: String?
    let revealed: Bool
    @State private var flipped = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let rate {
                let shownAmount = flipped ? rate.result : amount
                let shownResult = flipped ? amount : rate.result
                let (source, target) = flipped ? (to, from) : (from, to)
                QuestionLine(text: "\(shownAmount.formatted(.currency(code: source))) =")
                    .reveal(revealed)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Figure(text: shownResult.formatted(.currency(code: target)))
                    Text(Locale.current.localizedString(forCurrencyCode: target) ?? target)
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.textSecondary)
                        .contentTransition(.interpolate)
                    Spacer(minLength: 12)
                    SwapButton { withAnimation(Motion.spring(0.45)) { flipped.toggle() } }
                    CopyButton(text: String(format: "%.2f", shownResult))
                }
                .reveal(revealed, delay: 0.05)
                SourceLine(text: sourceText(rate))
                    .padding(.top, 8)
                    .reveal(revealed, delay: 0.1)
            } else if let failure {
                QuestionLine(text: String(localized: "\(amount.formatted(.currency(code: from))) in \(to)"))
                Text(failure)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                QuestionLine(text: "\(amount.formatted(.currency(code: from))) =")
                ShimmerText(text: String(localized: "Checking the rate"), font: .hero(30), base: Theme.textTertiary)
                    .frame(height: 52, alignment: .leading)
            }
        }
        .animation(Motion.outQuint(0.4), value: rate)
    }

    private func sourceText(_ rate: CurrencyClient.Rate) -> String {
        var day = rate.date
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        if let date = parser.date(from: rate.date) { day = date.formatted(.dateTime.month(.abbreviated).day()) }
        let unit = rate.amount > 0 ? rate.result / rate.amount : 0
        return String(localized: "1 \(from) = \(unit.formatted(.number.precision(.significantDigits(1...5)))) \(to) · the European Central Bank's rate of \(day), through Frankfurter")
    }
}

// MARK: - Time

private struct TimeAnswer: View {
    let city: String
    let zone: TimeZone
    let revealed: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 4) {
                QuestionLine(text: String(localized: "Time in \(city)"))
                    .reveal(revealed)
                Figure(text: context.date.formatted(Date.FormatStyle(timeZone: zone).hour().minute().second()), size: 52)
                    .reveal(revealed, delay: 0.05)
                Text(detail(at: context.date))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 2)
                    .reveal(revealed, delay: 0.1)
            }
        }
    }

    /// "Saturday, October 11 · GMT+9 · 7 hours ahead of you".
    private func detail(at date: Date) -> String {
        let day = date.formatted(Date.FormatStyle(timeZone: zone).weekday(.wide).month(.wide).day())
        let offset = zone.secondsFromGMT(for: date)
        let gmt = offset == 0 ? "GMT" : String(format: "GMT%@%d%@", offset > 0 ? "+" : "−", abs(offset) / 3600,
                                                 abs(offset) % 3600 == 0 ? "" : String(format: ":%02d", abs(offset) % 3600 / 60))
        let difference = offset - TimeZone.current.secondsFromGMT(for: date)
        let relative: String
        if difference == 0 {
            relative = String(localized: "same time as you")
        } else {
            let hours = abs(difference) / 3600, minutes = abs(difference) % 3600 / 60
            var amount = hours == 1 ? String(localized: "1 hour") : String(localized: "\(hours) hours")
            if hours == 0 { amount = String(localized: "\(minutes) min") } else if minutes > 0 { amount = String(localized: "\(amount) \(minutes) min") }
            relative = difference > 0 ? String(localized: "\(amount) ahead of you") : String(localized: "\(amount) behind you")
        }
        return "\(day) · \(gmt) · \(relative)"
    }
}

// MARK: - Weather

private struct WeatherAnswer: View {
    let report: WeatherReport?
    let failure: String?
    @State private var revealed = false

    var body: some View {
        Group {
            if let report {
                loaded(report)
                    .transition(.blurFade(radius: 3))
            } else if let failure {
                Text(failure)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ShimmerText(text: String(localized: "Checking the weather"), font: .system(size: 15), base: Theme.textTertiary)
                    SkeletonBar(width: 0.3, height: 40)
                    SkeletonBar(width: 0.5, height: 10, delay: 0.1)
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.outQuint(0.4), value: report)
    }

    private func loaded(_ report: WeatherReport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.place)
                        .font(.heading(20))
                        .tracking(-0.4)
                        .foregroundStyle(Theme.textPrimary)
                    if !report.region.isEmpty {
                        Text(report.region)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Figure(text: "\(Int(report.temperature.rounded()))°", size: 56)
                        Text(WeatherCondition.label(report.code))
                            .font(.system(size: 17))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.top, 6)
                    Text(String(localized: "Feels like \(Int(report.feelsLike.rounded()))° · Humidity \(report.humidity)% · Wind \(Int(report.wind.rounded())) \(report.windUnit)"))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                }
                .reveal(revealed)
                Spacer(minLength: 12)
                Icon(WeatherCondition.icon(report.code, isDay: report.isDay), size: 60, weight: 1.5)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 4)
                    .reveal(revealed, delay: 0.08, distance: 4)
            }

            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(report.days.enumerated()), id: \.element.id) { index, day in
                    DayColumn(day: day, isToday: index == 0, range: range(report))
                        .reveal(revealed, delay: 0.12 + Double(index) * 0.04)
                }
            }
            .padding(.top, 18)
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1).padding(.top, 2) }
            .padding(.top, 16)

            SourceLine(text: String(localized: "Weather from Open-Meteo, in \(report.temperatureUnit)"))
                .padding(.top, 14)
                .reveal(revealed, delay: 0.3)
        }
        .onAppear { revealed = true }
    }

    /// The week's lowest and highest, so each day's bar sits on the same scale.
    private func range(_ report: WeatherReport) -> ClosedRange<Double> {
        let low = report.days.map(\.low).min() ?? 0
        let high = report.days.map(\.high).max() ?? 1
        return low...max(high, low + 1)
    }
}

/// One day: its name, its weather, and its low and high on a bar that spans the week's range.
private struct DayColumn: View {
    let day: WeatherReport.Day
    let isToday: Bool
    let range: ClosedRange<Double>

    var body: some View {
        VStack(spacing: 8) {
            Text(name)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(isToday ? Theme.textPrimary : Theme.textTertiary)
            Icon(WeatherCondition.icon(day.code), size: 24)
                .foregroundStyle(Theme.textSecondary)
            GeometryReader { proxy in
                let span = range.upperBound - range.lowerBound
                let start = (day.low - range.lowerBound) / span
                let end = (day.high - range.lowerBound) / span
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hover)
                    Capsule()
                        .fill(Theme.textSecondary)
                        .frame(width: max(4, proxy.size.width * (end - start)))
                        .offset(x: proxy.size.width * start)
                }
            }
            .frame(width: 44, height: 4)
            HStack(spacing: 6) {
                Text("\(Int(day.high.rounded()))°").foregroundStyle(Theme.textPrimary)
                Text("\(Int(day.low.rounded()))°").foregroundStyle(Theme.textTertiary)
            }
            .font(.system(size: 13, weight: .medium))
            if let chance = day.precipitation, chance >= 30 {
                Text("\(chance)%")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var name: String {
        if isToday { return String(localized: "Today") }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: day.date) else { return day.date }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }
}
