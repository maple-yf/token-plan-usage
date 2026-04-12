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
                y: .value("次数", point.count)
            )
            .foregroundStyle(.blue.gradient)
            .interpolationMethod(.catmullRom)

            AreaMark(
                x: .value("时间", point.time),
                y: .value("次数", point.count)
            )
            .foregroundStyle(.blue.opacity(0.1).gradient)
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 1)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.quaternary)
                AxisValueLabel(format: .dateTime.hour().minute())
                    .font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.quaternary)
                AxisValueLabel()
                    .font(.caption2)
            }
        }
        .frame(height: 160)
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
            count: Int.random(in: 1...20)
        )
    }
    return UsageTrendChart(points: points)
        .background(.blue.opacity(0.3))
}
