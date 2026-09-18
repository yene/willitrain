//
//  ContentView.swift
//  willitrain
//
//  Created by yannick on 18.09.2026.
//

import SwiftUI
import WeatherKit
import CoreLocation

struct ContentView: View {
    enum LoadState {
        case loading
        case loaded(DaySummary)
        case failed(String)
    }

    @State private var loadState: LoadState = .loading

    var body: some View {
        Group {
            switch loadState {
            case .loading:
                ProgressView("Fetching weather…")
            case .loaded(let summary):
                summaryView(summary)
            case .failed(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .imageScale(.large)
                        .foregroundStyle(.orange)
                    Text(message)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        loadState = .loading
                        Task { await loadSummary() }
                    }
                }
            }
        }
        .padding()
        .task { await loadSummary() }
    }

    private func summaryView(_ summary: DaySummary) -> some View {
        VStack(spacing: 16) {
            Text(summary.isForTomorrow ? "Tomorrow" : "Today until 20:00")
                .font(.headline)
                .foregroundStyle(.secondary)

            Image(systemName: summary.symbolName)
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("\(formatTemperature(summary.lowCelsius)) – \(formatTemperature(summary.highCelsius))")
                .font(.title2)

            Text("Rain chance: \(summary.maxRainChance.formatted(.percent))")
                .foregroundStyle(.secondary)

            Divider()

            ForEach(summary.recommendations, id: \.self) { recommendation in
                Text(recommendation)
                    .font(.body)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func formatTemperature(_ celsius: Double) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .abbreviated, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    private func loadSummary() async {
        // Fixed location (Zurich) for now, until we add CoreLocation permissions
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

            if let summary = advisor.summarize(hours: hours, symbolName: symbolName, isForTomorrow: window.isForTomorrow) {
                loadState = .loaded(summary)
            } else {
                loadState = .failed("No forecast available for this time window.")
            }
        } catch {
            loadState = .failed("Couldn't load the weather: \(error.localizedDescription)")
        }
    }
}

#Preview {
    ContentView()
}
