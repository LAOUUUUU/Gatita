//
//  ChartBlockView.swift
//  Gatita
//

import Charts
import SwiftUI

/// Draws a chart block as a bar, line, or pie chart, with the title above it.
struct ChartBlockView: View {
    let spec: ChartSpec

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = spec.title, !title.isEmpty {
                Text(title)
                    .font(.callout.weight(.semibold))
            }
            switch spec.type {
            case "line":
                lineChart
            case "pie":
                pieChart
            default:
                barChart
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12)))
    }

    /// The labels along the bottom, with no vertical grid lines through the chart.
    private var labelsOnly: some AxisContent {
        AxisMarks { _ in
            AxisValueLabel()
        }
    }

    private var barChart: some View {
        Chart(Array(spec.points.enumerated()), id: \.offset) { _, point in
            BarMark(x: .value("Label", point.label), y: .value("Value", point.value))
                .foregroundStyle(Theme.accent)
        }
        .chartXAxis { labelsOnly }
        .frame(height: 220)
    }

    private var lineChart: some View {
        Chart(Array(spec.points.enumerated()), id: \.offset) { _, point in
            LineMark(x: .value("Label", point.label), y: .value("Value", point.value))
                .foregroundStyle(Theme.accent)
            PointMark(x: .value("Label", point.label), y: .value("Value", point.value))
                .foregroundStyle(Theme.accent)
        }
        .chartXAxis { labelsOnly }
        .frame(height: 220)
    }

    private var pieChart: some View {
        Chart(Array(spec.points.enumerated()), id: \.offset) { _, point in
            SectorMark(angle: .value("Value", point.value), innerRadius: .ratio(0.55))
                .foregroundStyle(by: .value("Label", point.label))
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 240)
    }
}
