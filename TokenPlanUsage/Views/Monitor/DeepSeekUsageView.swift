import SwiftUI
import Charts

struct DeepSeekUsageView: View {
    let usage: DeepSeekPlatformUsage
    let balance: DeepSeekBalance?
    let isLoading: Bool
    let errorMessage: String?
    var onRefresh: (() -> Void)?
    var onMonthChange: ((Int, Int) -> Void)?

    @State private var selectedMonth: Date
    @State private var selectedDataPoint: DeepSeekDailyUsage?

    init(usage: DeepSeekPlatformUsage, balance: DeepSeekBalance?, isLoading: Bool, errorMessage: String?, onRefresh: (() -> Void)?, onMonthChange: ((Int, Int) -> Void)?) {
        self.usage = usage
        self.balance = balance
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.onRefresh = onRefresh
        self.onMonthChange = onMonthChange

        let calendar = Calendar.current
        let components = DateComponents(year: usage.year, month: usage.month)
        _selectedMonth = State(initialValue: calendar.date(from: components) ?? Date())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard
                monthSelector
                if isLoading {
                    loadingCharts
                } else if let error = errorMessage {
                    errorCard(error)
                } else if usage.dailyUsage.isEmpty {
                    emptyCard
                } else {
                    chartsSection
                    modelDetailSection
                    tokenBreakdownSection
                }
            }
            .padding()
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.doc.horizontal.fill")
                    .foregroundStyle(.orange)
                Text("用量信息")
                    .font(.headline)
                Spacer()
                if let onRefresh {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline)
                    }
                }
            }

            Divider()

            HStack(spacing: 0) {
                summaryItem(
                    title: "充值余额",
                    value: balance.flatMap { "\($0.currency) \($0.totalBalance)" } ?? "---",
                    color: .green
                )
                summaryItem(
                    title: "本月消费",
                    value: String(format: "%@ %.2f", usage.currency, usage.totalConsumption),
                    color: .orange
                )
                summaryItem(
                    title: "总请求数",
                    value: formatRequestCount(usage.totalRequests),
                    color: .blue
                )
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func summaryItem(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Month Selector

    private var monthSelector: some View {
        HStack {
            Button {
                changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline)
            }

            DatePicker("", selection: $selectedMonth, displayedComponents: [.date])
                .datePickerStyle(.compact)
                .labelsHidden()
                .onChange(of: selectedMonth) { _, newDate in
                    let calendar = Calendar.current
                    let month = calendar.component(.month, from: newDate)
                    let year = calendar.component(.year, from: newDate)
                    onMonthChange?(month, year)
                }

            Button {
                changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline)
            }
            .disabled(isCurrentMonth)

            Spacer()

            Button {
                // Export placeholder
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var isCurrentMonth: Bool {
        let calendar = Calendar.current
        let now = Date()
        return calendar.component(.month, from: selectedMonth) == calendar.component(.month, from: now) &&
               calendar.component(.year, from: selectedMonth) == calendar.component(.year, from: now)
    }

    private func changeMonth(by delta: Int) {
        guard let newDate = Calendar.current.date(byAdding: .month, value: delta, to: selectedMonth) else { return }
        let now = Date()
        if newDate > now { return }
        selectedMonth = newDate
        let month = Calendar.current.component(.month, from: newDate)
        let year = Calendar.current.component(.year, from: newDate)
        onMonthChange?(month, year)
    }

    // MARK: - Charts Section

    private var chartsSection: some View {
        VStack(spacing: 12) {
            consumptionBarChart
            apiRequestChart
            tokenStackedBarChart
        }
    }

    // Chart 1: Consumption amount bar chart (orange)
    private var consumptionBarChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("消费金额", systemImage: "yensign.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            Chart(usage.dailyUsage) { day in
                BarMark(
                    x: .value("日期", formatDateLabel(day.date)),
                    y: .value("金额", day.totalAmount)
                )
                .foregroundStyle(.orange.gradient)
            }
            .chartXAxis {
                AxisMarks(values: xAxisDateLabels) { value in
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(String(format: "%.0f", v))
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 150)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // Chart 2: API request count area + line chart (light blue)
    private var apiRequestChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("API 请求次数", systemImage: "arrow.triangle.branch")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)

            Chart(usage.dailyUsage) { day in
                AreaMark(
                    x: .value("日期", formatDateLabel(day.date)),
                    y: .value("请求数", day.requestCount)
                )
                .foregroundStyle(.blue.opacity(0.15).gradient)
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("日期", formatDateLabel(day.date)),
                    y: .value("请求数", day.requestCount)
                )
                .foregroundStyle(.blue.gradient)
                .interpolationMethod(.catmullRom)
            }
            .chartXAxis {
                AxisMarks(values: xAxisDateLabels) { value in
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(String(format: "%.0f", v))
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 150)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // Chart 3: Token consumption stacked bar chart (three shades of blue)
    private var tokenStackedBarChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Tokens 消耗量", systemImage: "square.stack.3d.up.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)

            Chart(usage.dailyUsage) { day in
                BarMark(
                    x: .value("日期", formatDateLabel(day.date)),
                    y: .value("命中缓存", day.cacheHitTokens)
                )
                .foregroundStyle(.cyan.opacity(0.7))

                BarMark(
                    x: .value("日期", formatDateLabel(day.date)),
                    y: .value("未命中缓存", day.cacheMissTokens)
                )
                .foregroundStyle(.blue.opacity(0.7))

                BarMark(
                    x: .value("日期", formatDateLabel(day.date)),
                    y: .value("输出", day.outputTokens)
                )
                .foregroundStyle(.indigo.opacity(0.8))
            }
            .chartXAxis {
                AxisMarks(values: xAxisDateLabels) { value in
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(String(format: "%.1f", v))
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 170)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Model Detail Section

    private var modelDetailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("模型详情", systemImage: "server.rack")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            ForEach(usage.modelTotals) { model in
                modelDetailRow(model)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func modelDetailRow(_ model: DeepSeekModelTotalUsage) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(model.modelName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
            }

            HStack(spacing: 0) {
                detailStatItem(title: "API 请求", value: formatRequestCount(model.requestCount), color: .blue)
                detailStatItem(title: "Tokens 消耗", value: String(format: "%.2f", model.totalAmount), color: .purple)
            }

            HStack(spacing: 6) {
                tokenTypeDot(color: .cyan, label: "命中")
                Text(String(format: "%.4f", model.cacheHitTokens))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                tokenTypeDot(color: .blue, label: "未命中")
                Text(String(format: "%.4f", model.cacheMissTokens))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                tokenTypeDot(color: .indigo, label: "输出")
                Text(String(format: "%.4f", model.outputTokens))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func detailStatItem(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Token Breakdown Section

    private var tokenBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Token 细分", systemImage: "square.split.2x2.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            HStack(spacing: 12) {
                tokenBreakdownItem(
                    color: .cyan,
                    title: "输入（命中缓存）",
                    value: usage.modelTotals.reduce(0) { $0 + $1.cacheHitTokens }
                )
                tokenBreakdownItem(
                    color: .blue,
                    title: "输入（未命中缓存）",
                    value: usage.modelTotals.reduce(0) { $0 + $1.cacheMissTokens }
                )
                tokenBreakdownItem(
                    color: .indigo,
                    title: "输出",
                    value: usage.modelTotals.reduce(0) { $0 + $1.outputTokens }
                )
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func tokenBreakdownItem(color: Color, title: String, value: Double) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(String(format: "\(usage.currency) %.4f", value))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Loading / Error / Empty

    private var loadingCharts: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary)
                    .frame(height: 150)
                    .overlay {
                        ProgressView()
                            .tint(.secondary)
                    }
            }
        }
    }

    private func errorCard(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(msg)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let onRefresh {
                Button("重试", action: onRefresh)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var emptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("暂无用量数据")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Helpers

    private func formatDateLabel(_ dateStr: String) -> String {
        let parts = dateStr.split(separator: "-")
        guard parts.count >= 3 else { return dateStr }
        return "\(parts[1])/\(parts[2])"
    }

    private var xAxisDateLabels: [String] {
        guard !usage.dailyUsage.isEmpty else { return [] }
        let count = usage.dailyUsage.count
        guard count > 5 else { return usage.dailyUsage.map { formatDateLabel($0.date) } }
        let step = max(1, count / 5)
        return stride(from: 0, to: count, by: step).map { formatDateLabel(usage.dailyUsage[$0].date) }
    }

    private func formatRequestCount(_ count: Double) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", count / 1000)
        }
        return String(format: "%.0f", count)
    }

    private func tokenTypeDot(color: Color, label: String) -> some View {
        HStack(spacing: 2) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    let sample = DeepSeekPlatformUsage(
        currency: "CNY",
        year: 2026,
        month: 5,
        dailyUsage: [
            DeepSeekDailyUsage(date: "2026-05-01", totalAmount: 0, requestCount: 0, cacheHitTokens: 0, cacheMissTokens: 0, outputTokens: 0, modelBreakdown: []),
            DeepSeekDailyUsage(date: "2026-05-02", totalAmount: 1.5, requestCount: 3, cacheHitTokens: 0.2, cacheMissTokens: 0.9, outputTokens: 0.4, modelBreakdown: []),
            DeepSeekDailyUsage(date: "2026-05-03", totalAmount: 2.8, requestCount: 5, cacheHitTokens: 0.4, cacheMissTokens: 1.6, outputTokens: 0.8, modelBreakdown: []),
            DeepSeekDailyUsage(date: "2026-05-04", totalAmount: 1.2, requestCount: 2, cacheHitTokens: 0.1, cacheMissTokens: 0.7, outputTokens: 0.4, modelBreakdown: []),
            DeepSeekDailyUsage(date: "2026-05-05", totalAmount: 3.5, requestCount: 8, cacheHitTokens: 0.5, cacheMissTokens: 2.0, outputTokens: 1.0, modelBreakdown: [])
        ],
        modelTotals: [
            DeepSeekModelTotalUsage(modelName: "deepseek-v4-pro", cacheHitTokens: 0.8, cacheMissTokens: 4.0, outputTokens: 2.0, requestCount: 12, totalAmount: 6.8),
            DeepSeekModelTotalUsage(modelName: "deepseek-v4-flash", cacheHitTokens: 0.4, cacheMissTokens: 1.2, outputTokens: 0.6, requestCount: 6, totalAmount: 2.2)
        ]
    )
    return DeepSeekUsageView(
        usage: sample,
        balance: DeepSeekBalance(currency: "CNY", totalBalance: "50.77", grantedBalance: "0.00", toppedUpBalance: "50.77"),
        isLoading: false,
        errorMessage: nil,
        onRefresh: {},
        onMonthChange: { _, _ in }
    )
    .background(.blue.opacity(0.3))
}
