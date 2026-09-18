//
//  WeatherAdvisor.swift
//  willitrain
//

import Foundation

/// One hour of forecast data reduced to the plain values the rules need,
/// so the advisor stays independent of WeatherKit types.
struct HourSample {
    let date: Date
    let temperatureCelsius: Double
    let precipitationChance: Double
    let rainfallMillimeters: Double
}

/// The day's weather in a nutshell plus what-to-wear recommendations.
struct DaySummary {
    let isForTomorrow: Bool
    let symbolName: String
    let lowCelsius: Double
    let highCelsius: Double
    let maxRainChance: Double
    let recommendations: [String]
}

/// Applies the WearRules thresholds to a day's hourly forecast.
struct WeatherAdvisor {
    let rules: WearRules
    var calendar = Calendar.current

    /// The forecast window per SPEC.md: now until 20:00 today, or tomorrow
    /// 06:00–20:00 when opened after 20:00. The start is floored to the hour
    /// so the current hour's forecast entry is included.
    func forecastWindow(now: Date = .now) -> (start: Date, end: Date, isForTomorrow: Bool) {
        let todayEnd = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now)!
        if now < todayEnd {
            let start = calendar.dateInterval(of: .hour, for: now)!.start
            return (start, todayEnd, false)
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let start = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: tomorrow)!
        let end = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: tomorrow)!
        return (start, end, true)
    }

    /// Returns nil when there are no hours in the window.
    func summarize(hours: [HourSample], symbolName: String, isForTomorrow: Bool) -> DaySummary? {
        guard let firstHour = hours.first else { return nil }

        let temperatures = hours.map(\.temperatureCelsius)
        let low = temperatures.min()!
        let high = temperatures.max()!
        let maxRainChance = hours.map(\.precipitationChance).max()!

        var recommendations: [String] = []

        if maxRainChance >= rules.rainChanceThreshold {
            let peak = hours.max { $0.precipitationChance < $1.precipitationChance }!
            let time = peak.date.formatted(date: .omitted, time: .shortened)
            recommendations.append("It will rain (\(maxRainChance.formatted(.percent)) chance around \(time)) — you need an umbrella.")
        }

        if low < rules.coldBelowCelsius {
            recommendations.append("It will be cold (low around \(formatTemperature(low))) — wear a jacket.")
        }

        // Evening = 17:00–20:00, when the SPEC.md persona heads home from work.
        let eveningLow = hours
            .filter { (17..<20).contains(calendar.component(.hour, from: $0.date)) }
            .map(\.temperatureCelsius)
            .min()
        if let eveningLow, firstHour.temperatureCelsius - eveningLow >= rules.eveningDropCelsius {
            recommendations.append("It will be colder in the evening (around \(formatTemperature(eveningLow))) — bring extra clothes.")
        }

        if recommendations.isEmpty {
            recommendations.append("Nothing special needed — enjoy your day.")
        }

        return DaySummary(
            isForTomorrow: isForTomorrow,
            symbolName: symbolName,
            lowCelsius: low,
            highCelsius: high,
            maxRainChance: maxRainChance,
            recommendations: recommendations
        )
    }

    private func formatTemperature(_ celsius: Double) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .abbreviated, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}
