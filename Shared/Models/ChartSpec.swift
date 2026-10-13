//
//  ChartSpec.swift
//  Gatita
//

import Foundation

/// The data in a chart block: a bar, line, or pie chart with one value per label.
nonisolated struct ChartSpec: Codable, Equatable, Sendable {
    struct Point: Codable, Equatable, Sendable {
        let label: String
        let value: Double
    }

    static let kinds = ["bar", "line", "pie"]
    static let maxPoints = 50

    let type: String
    let title: String?
    let points: [Point]

    /// The chart in a chart block's JSON, or nil when the JSON is not a chart this app can draw.
    static func parse(_ json: String) -> ChartSpec? {
        guard let data = json.data(using: .utf8),
              let spec = try? JSONDecoder().decode(ChartSpec.self, from: data),
              kinds.contains(spec.type),
              !spec.points.isEmpty,
              spec.points.count <= maxPoints else { return nil }
        return spec
    }
}
