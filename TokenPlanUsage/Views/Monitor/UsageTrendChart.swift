import SwiftUI
import Charts

struct UsageTrendChart: View {
    let points: [UsagePoint]
    var selectedTimeRange: TimeRange = .day
    var totalTokens: Int? = nil
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var onTimeRangeChange: ((TimeRange) -> Void)?
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("用量趋势")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let total = totalTokens {
                        Text("总计 \(Self.formatTokenCount(total)) tokens")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                timeRangePicker
            }

            if isLoading {
                loadingState
            } else if errorMessage != nil {
                errorState
            } else if points.isEmpty {
                emptyState
            } else {
                chartContent
            }
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("用量趋势图表，共 \(points.count) 个数据点")
    }

    private var timeRangePicker: some View {
        HStack(spacing: 0) {
            ForEach(TimeRange.allCases) { range in
                Button {
                    onTimeRangeChange?(range)
                } label: {
                    Text(range.rawValue)
                        .font(.caption2.weight(selectedTimeRange == range ? .semibold : .regular))
                        .foregroundStyle(selectedTimeRange == range ? .primary : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            selectedTimeRange == range
                                ? AnyShapeStyle(.ultraThinMaterial)
                                : AnyShapeStyle(.clear)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(3)
        .background(.ultraThinMaterial.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
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
                AxisValueLabel(format: xAxisDateFormat)
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

    /// Adaptive date format based on selected time range
    private var xAxisDateFormat: Date.FormatStyle {
        switch selectedTimeRange {
        case .day:
            return .dateTime.hour().minute()
        case .week:
            return .dateTime.weekday(.abbreviated).day()
        case .month:
            return .dateTime.month(.abbreviated).day()
        }
    }

    /// Smart unit: K / M / G / T
    private static func formatTokenCount(_ count: Int) -> String {
        let thresholds: [(divisor: Double, suffix: String)] = [
            (1_000_000_000_000.0, "T"),
            (1_000_000_000.0, "G"),
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

    private var loadingState: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.quaternary)
            .frame(height: 160)
            .overlay {
                ProgressView()
                    .tint(.secondary)
            }
    }

    private var errorState: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.quaternary)
            .frame(height: 160)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("加载失败")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("重试") {
                        onRetry?()
                    }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
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
