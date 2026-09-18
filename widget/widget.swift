//
//  widget.swift
//  widget
//
//  Created by yannick on 18.09.2026.
//

import WidgetKit
import SwiftUI
import WeatherKit
import CoreLocation

struct WeatherEntry: TimelineEntry {
    let date: Date
    /// nil when the forecast couldn't be loaded.
    let summary: DaySummary?
}

struct Provider: TimelineProvider {
    static let sampleSummary = DaySummary(
        isForTomorrow: false,
        symbolName: "cloud.sun",
        lowCelsius: 14,
        highCelsius: 19,
        maxRainChance: 0.4,
        recommendations: ["It will rain — you need an umbrella."],
        shortRecommendation: "Take an umbrella"
    )

    func placeholder(in context: Context) -> WeatherEntry {
        WeatherEntry(date: .now, summary: Self.sampleSummary)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeatherEntry) -> ()) {
        // The widget gallery gets sample data; a real snapshot fetches the forecast.
        if context.isPreview {
            completion(WeatherEntry(date: .now, summary: Self.sampleSummary))
            return
        }
        Task {
            let entries = await makeEntries()
            completion(entries.first ?? WeatherEntry(date: .now, summary: nil))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherEntry>) -> ()) {
        Task {
            let entries = await makeEntries()
            // Ask for a fresh forecast every couple of hours (sooner after a
            // failure); the system budgets the exact timing.
            let refreshDelay: TimeInterval = entries.first?.summary == nil ? 30 * 60 : 2 * 60 * 60
            completion(Timeline(entries: entries, policy: .after(.now.addingTimeInterval(refreshDelay))))
        }
    }

    /// Fetches the forecast once and derives one entry per hour: each entry
    /// re-summarizes only the remaining hours, so recommendations that have
    /// passed (e.g. rain at 14:00) drop off without another fetch.
    private func makeEntries() async -> [WeatherEntry] {
        // Fixed location (Zurich) for now, same as the app.
        let location = CLLocation(latitude: 47.37, longitude: 8.54)

        do {
            let rules = try WearRules.load()
            let advisor = WeatherAdvisor(rules: rules)
            let weather = try await WeatherService.shared.weather(for: location)

            let window = advisor.forecastWindow()
            let hours = weather.hourlyForecast
                .filter { $0.date >= window.start && $0.date < window.end }
                .map { hour in
                    HourSample(
                        date: hour.date,
                        temperatureCelsius: hour.temperature.converted(to: .celsius).value,
                        precipitationChance: hour.precipitationChance,
                        rainfallMillimeters: hour.precipitationAmount.converted(to: .millimeters).value
                    )
                }

            let symbolName = weather.dailyForecast
                .first { advisor.calendar.isDate($0.date, inSameDayAs: window.start) }?
                .symbolName ?? weather.currentWeather.symbolName

            var entries = [WeatherEntry(
                date: .now,
                summary: advisor.summarize(hours: hours, symbolName: symbolName, isForTomorrow: window.isForTomorrow)
            )]

            if !window.isForTomorrow {
                for index in hours.indices.dropFirst() {
                    let remaining = Array(hours[index...])
                    entries.append(WeatherEntry(
                        date: hours[index].date,
                        summary: advisor.summarize(hours: remaining, symbolName: symbolName, isForTomorrow: false)
                    ))
                }
            }

            return entries
        } catch {
            return [WeatherEntry(date: .now, summary: nil)]
        }
    }
}

struct widgetEntryView: View {
    var entry: WeatherEntry

    var body: some View {
        if let summary = entry.summary {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: summary.symbolName)
                        .font(.title2)
                        .foregroundStyle(.tint)
                    Spacer()
                    if summary.isForTomorrow {
                        Text("Tomorrow")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text("\(Int(summary.lowCelsius.rounded()))° – \(Int(summary.highCelsius.rounded()))°")
                    .font(.title3.bold())

                Text("\(summary.maxRainChance.formatted(.percent)) rain")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(summary.shortRecommendation)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "cloud.sun")
                    .foregroundStyle(.secondary)
                Text("Weather unavailable")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

struct widget: Widget {
    let kind: String = "willitrain.today"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            widgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Will It Rain")
        .description("Today's weather and what to wear.")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    widget()
} timeline: {
    WeatherEntry(date: .now, summary: Provider.sampleSummary)
    WeatherEntry(date: .now, summary: nil)
}
