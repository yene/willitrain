//
//  WearRules.swift
//  willitrain
//

import Foundation

/// Thresholds for the wear recommendations, loaded from WearRules.json
/// so they can be tweaked without touching code (see SPEC.md).
struct WearRules: Codable {
    /// Recommend an umbrella when any hour's precipitation chance reaches this fraction (0...1).
    var rainChanceThreshold: Double
    /// Recommend a jacket when the day's low falls below this temperature.
    var coldBelowCelsius: Double
    /// Recommend extra clothes when the evening is at least this much colder than now.
    var eveningDropCelsius: Double

    enum LoadError: LocalizedError {
        case fileMissing

        var errorDescription: String? {
            "WearRules.json is missing from the app bundle"
        }
    }

    static func load(from bundle: Bundle = .main) throws -> WearRules {
        guard let url = bundle.url(forResource: "WearRules", withExtension: "json") else {
            throw LoadError.fileMissing
        }
        return try JSONDecoder().decode(WearRules.self, from: Data(contentsOf: url))
    }
}
