import SwiftUI
import Charts

struct UsageTrendChart: View {
    let points: [UsagePoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("用量趋势")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            if points.isEmpty {
                emptyState
            } else {
                chartContent
            }
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("用量趋势图表，共 \(points.count) 个数据点")
    }

    private var chartContent: some View {
        Chart(points) { point in
            LineMark(
                x: .value("时间", point.time),
                y: .value("Tokens", point.count)
            )
            .foregroundStyle(.blue.gradient)
            .interpolationMethod(.catmullRom)

            AreaMark(
                x: .value("时间", point.time),
                y: .value("Tokens", point.count)
            )
            .foregroundStyle(.blue.opacity(0.1).gradient)
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis {
            AxisMarks(values: xAxisValues) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.quaternary)
                AxisValueLabel(format: .dateTime.hour().minute())
                    .font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let intValue = value.as(Int.self) {
                        Text(Self.formatTokenCount(intValue))
                            .font(.caption2)
                    }
                }
            }
        }
        .frame(height: 160)
    }

    /// Smart unit: K / M / G / B
    private static func formatTokenCount(_ count: Int) -> String {
        let thresholds: [(divisor: Double, suffix: String)] = [
            (1_000_000_000.0, "B"),
            (1_000_000.0, "M"),
            (1_000.0, "K"),
        ]
        for (divisor, suffix) in thresholds {
            if Double(count) >= divisor {
                let value = Double(count) / divisor
                return value == floor(value) ? "\(Int(value))\(suffix)" : String(format: "%.1f\(suffix)", value)
            }
        }
        return "\(count)"
    }

    /// Pick 5 evenly spaced time values from the data points for x-axis labels
    private var xAxisValues: [Date] {
        guard points.count > 5 else { return points.map(\.time) }
        return (0..<5).map { i in
            let index = Double(i) / 4.0 * Double(points.count - 1)
            let lower = Int(index.rounded(.down))
            let upper = min(lower + 1, points.count - 1)
            let frac = index - Double(lower)
            return points[lower].time.addingTimeInterval(
                points[upper].time.timeIntervalSince(points[lower].time) * frac
            )
        }
    }

    private var emptyState: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.quaternary)
            .frame(height: 160)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("暂无趋势数据")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("暂无趋势数据")
            }
    }
}

#Preview {
    let points = (0..<10).map { i in
        UsagePoint(
            time: Date().addingTimeInterval(-Double(9 - i) * 1800),
            count: Int.random(in: 1...20000)
        )
    }
    return UsageTrendChart(points: points)
        .background(.blue.opacity(0.3))
}
