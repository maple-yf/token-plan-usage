import SwiftUI
import Charts

struct DeepSeekUsageView: View {
    let usage: DeepSeekPlatformUsage
    let balance: DeepSeekBalance?
    let isLoading: Bool
    let errorMessage: String?
    let monthlyTrend: [MonthlyConsumptionPoint]
    let isMonthlyTrendLoading: Bool
    let monthlyTrendErrorMessage: String?
    var onRefresh: (() -> Void)?
    var onMonthChange: ((Int, Int) -> Void)?

    @State private var selectedMonth: Date
    @State private var selectedDataPoint: DeepSeekDailyUsage?

    private static let chineseMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月"
        return f
    }()

    init(usage: DeepSeekPlatformUsage, balance: DeepSeekBalance?, isLoading: Bool, errorMessage: String?, monthlyTrend: [MonthlyConsumptionPoint], isMonthlyTrendLoading: Bool, monthlyTrendErrorMessage: String?, onRefresh: (() -> Void)?, onMonthChange: ((Int, Int) -> Void)?) {
        self.usage = usage
        self.balance = balance
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.monthlyTrend = monthlyTrend
        self.isMonthlyTrendLoading = isMonthlyTrendLoading
        self.monthlyTrendErrorMessage = monthlyTrendErrorMessage
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

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                statCard(
                    icon: "creditcard.fill",
                    title: "充值余额",
                    value: balance.flatMap { "\($0.currency) \($0.totalBalance)" } ?? "---",
                    color: .green
                )
                statCard(
                    icon: "yensign.circle.fill",
                    title: "本月消费",
                    value: String(format: "%@ %.2f", usage.currency, usage.totalConsumption),
                    color: .orange
                )
                statCard(
                    icon: "square.stack.3d.up.fill",
                    title: "总 Tokens",
                    value: formatTokenCount(Int(usage.totalTokens)),
                    color: .purple
                )
                statCard(
                    icon: "arrow.triangle.branch",
                    title: "总请求数",
                    value: "\(Int(usage.totalRequests))",
                    color: .blue
                )
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func statCard(icon: String, title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Month Selector

    private var monthSelector: some View {
        HStack(spacing: 8) {
            Button {
                changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline)
            }

            Picker("年", selection: yearBinding) {
                ForEach(availableYears, id: \.self) { year in
                    Text("\(String(year))年").tag(year)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()

            Picker("月", selection: monthBinding) {
                ForEach(1...12, id: \.self) { month in
                    Text("\(month)月").tag(month)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
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

    private var availableYears: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array((currentYear - 5)...currentYear)
    }

    private var yearBinding: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.year, from: selectedMonth) },
            set: { newYear in
                let calendar = Calendar.current
                let month = calendar.component(.month, from: selectedMonth)
                let newDate = calendar.date(from: DateComponents(year: newYear, month: month, day: 1)) ?? selectedMonth
                selectedMonth = newDate
            }
        )
    }

    private var monthBinding: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.month, from: selectedMonth) },
            set: { newMonth in
                let calendar = Calendar.current
                let year = calendar.component(.year, from: selectedMonth)
                let newDate = calendar.date(from: DateComponents(year: year, month: newMonth, day: 1)) ?? selectedMonth
                selectedMonth = newDate
            }
        )
    }

    // MARK: - Charts Section

    private var chartsSection: some View {
        VStack(spacing: 12) {
            consumptionBarChart
            monthlyTrendSection
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
                    y: .value("金额", day.totalCost)
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
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(formatCostAxisLabel(v))
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
    @ViewBuilder
    private var apiRequestChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("API 请求次数", systemImage: "arrow.triangle.branch")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)

            if usage.totalRequests > 0 {
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
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(formatRequestAxisLabel(v))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 150)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("当前计费不按请求次数统计")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("可查看下方模型费用分布")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 150)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // Chart 3: Token distribution stacked bar chart — values are real token counts from /usage/amount
    private var tokenStackedBarChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Tokens 分布", systemImage: "square.stack.3d.up.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)

            Chart(usage.dailyUsage) { day in
                BarMark(
                    x: .value("日期", formatDateLabel(day.date)),
                    y: .value("命中缓存", day.promptCacheHitTokens)
                )
                .foregroundStyle(.cyan.opacity(0.7))

                BarMark(
                    x: .value("日期", formatDateLabel(day.date)),
                    y: .value("未命中缓存", day.promptCacheMissTokens)
                )
                .foregroundStyle(.blue.opacity(0.7))

                BarMark(
                    x: .value("日期", formatDateLabel(day.date)),
                    y: .value("输出", day.responseTokens)
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
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(formatTokenAxisLabel(v))
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
                detailStatItem(
                    title: "API 请求",
                    value: "\(Int(model.requestCount))",
                    color: .blue
                )
                detailStatItem(
                    title: "Tokens 消耗",
                    value: formatTokenCount(Int(model.totalTokens)),
                    color: .purple
                )
                detailStatItem(
                    title: "费用消耗",
                    value: String(format: "%@ %.2f", usage.currency, model.totalCost),
                    color: .orange
                )
            }

            HStack(spacing: 6) {
                tokenTypeDot(color: .cyan, label: "命中")
                Text(formatTokenCount(Int(model.promptCacheHitTokens)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                tokenTypeDot(color: .blue, label: "未命中")
                Text(formatTokenCount(Int(model.promptCacheMissTokens)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                tokenTypeDot(color: .indigo, label: "输出")
                Text(formatTokenCount(Int(model.responseTokens)))
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
            Label("Tokens 细分", systemImage: "square.split.2x2.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            HStack(spacing: 12) {
                tokenBreakdownItem(
                    color: .cyan,
                    title: "输入（命中缓存）",
                    value: usage.modelTotals.reduce(0) { $0 + $1.promptCacheHitTokens }
                )
                tokenBreakdownItem(
                    color: .blue,
                    title: "输入（未命中缓存）",
                    value: usage.modelTotals.reduce(0) { $0 + $1.promptCacheMissTokens }
                )
                tokenBreakdownItem(
                    color: .indigo,
                    title: "输出",
                    value: usage.modelTotals.reduce(0) { $0 + $1.responseTokens }
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
            Text(formatTokenCount(Int(value)))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Monthly Trend Section

    private var monthlyTrendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("月度消费趋势", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
                if !monthlyTrend.isEmpty {
                    Text("近 \(monthlyTrend.count) 个月")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if isMonthlyTrendLoading && monthlyTrend.isEmpty {
                trendPlaceholder { ProgressView().tint(.secondary) }
            } else if monthlyTrend.isEmpty {
                trendPlaceholder {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("暂无月度消费数据")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Chart(monthlyTrend) { point in
                    LineMark(
                        x: .value("月份", point.month, unit: .month),
                        y: .value("消费", point.consumption)
                    )
                    .foregroundStyle(.orange.gradient)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))

                    AreaMark(
                        x: .value("月份", point.month, unit: .month),
                        y: .value("消费", point.consumption)
                    )
                    .foregroundStyle(.orange.opacity(0.15).gradient)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("月份", point.month, unit: .month),
                        y: .value("消费", point.consumption)
                    )
                    .foregroundStyle(.orange)
                    .symbolSize(50)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(Self.chineseMonthFormatter.string(from: date))
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        .font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(formatTrendCostLabel(v))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 160)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func trendPlaceholder<C: View>(@ViewBuilder content: () -> C) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.quaternary)
            .frame(height: 160)
            .overlay { content() }
    }

    private func formatTrendCostLabel(_ value: Double) -> String {
        let symbol = currencySymbol(for: monthlyTrend.first?.currency ?? "CNY")
        if abs(value) >= 1 {
            return String(format: "%@%.1f", symbol, value)
        } else if abs(value) >= 0.01 {
            return String(format: "%@%.2f", symbol, value)
        } else {
            return String(format: "%@%.3f", symbol, value)
        }
    }

    // MARK: - Loading / Error / Empty

    /// Full-screen skeleton used for the **initial** load (when
    /// `platformUsage` is still nil in the parent MonitorView). Mirrors the
    /// summary card, month selector, four chart panels, model list, and
    /// token breakdown so the user sees the eventual layout at a glance.
    /// Exposed as a static view so the parent can render it before
    /// `DeepSeekUsageView` itself has any data to bind to.
    static var loadingView: some View {
        VStack(spacing: 16) {
            summaryCardSkeleton
            monthSelectorSkeleton
            VStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    Self.skeletonChart
                }
                Self.skeletonModelDetail
                Self.skeletonTokenBreakdown
            }
        }
    }

    /// Mirrors the real chartsSection / modelDetailSection /
    /// tokenBreakdownSection layout with shimmering placeholders. Used
    /// for **refreshes** (after data has loaded at least once) — at that
    /// point the summaryCard and monthSelector still show the previous
    /// values, so we only skeleton the data section.
    private var loadingCharts: some View {
        VStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in
                Self.skeletonChart
            }
            Self.skeletonModelDetail
            Self.skeletonTokenBreakdown
        }
    }

    private static var summaryCardSkeleton: some View {
        VStack(spacing: 12) {
            HStack {
                SkeletonView(cornerRadius: 4).frame(width: 80, height: 16)
                Spacer()
                SkeletonView(cornerRadius: 4).frame(width: 24, height: 16)
            }
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(0..<4, id: \.self) { _ in
                    statCardSkeleton
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private static var statCardSkeleton: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                SkeletonView(cornerRadius: 2).frame(width: 10, height: 10)
                SkeletonView(cornerRadius: 2).frame(width: 40, height: 10)
            }
            SkeletonView(cornerRadius: 4).frame(width: 80, height: 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private static var monthSelectorSkeleton: some View {
        HStack(spacing: 8) {
            SkeletonView(cornerRadius: 12).frame(width: 24, height: 24)
            SkeletonView(cornerRadius: 6).frame(width: 60, height: 24)
            SkeletonView(cornerRadius: 6).frame(width: 40, height: 24)
            SkeletonView(cornerRadius: 12).frame(width: 24, height: 24)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private static var skeletonChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonView(cornerRadius: 4).frame(width: 100, height: 14)
            SkeletonView(cornerRadius: 12).frame(height: 150)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private static var skeletonModelDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonView(cornerRadius: 4).frame(width: 80, height: 14)
            ForEach(0..<2, id: \.self) { _ in
                skeletonModelRow
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private static var skeletonModelRow: some View {
        VStack(spacing: 8) {
            HStack {
                SkeletonView(cornerRadius: 4).frame(width: 120, height: 12)
                Spacer()
            }
            HStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(spacing: 2) {
                        SkeletonView(cornerRadius: 4).frame(width: 50, height: 14)
                        SkeletonView(cornerRadius: 3).frame(width: 36, height: 10)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 2) {
                        Circle().fill(.quaternary).frame(width: 5, height: 5)
                        SkeletonView(cornerRadius: 3).frame(width: 28, height: 10)
                        SkeletonView(cornerRadius: 3).frame(width: 36, height: 10)
                    }
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private static var skeletonTokenBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonView(cornerRadius: 4).frame(width: 80, height: 14)
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Circle().fill(.quaternary).frame(width: 8, height: 8)
                            SkeletonView(cornerRadius: 3).frame(width: 60, height: 10)
                        }
                        SkeletonView(cornerRadius: 4).frame(width: 50, height: 14)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
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

    private func formatCostAxisLabel(_ value: Double) -> String {
        let symbol = currencySymbol(for: usage.currency)
        if abs(value) >= 1 {
            return String(format: "%@%.1f", symbol, value)
        } else if abs(value) >= 0.01 {
            return String(format: "%@%.2f", symbol, value)
        } else {
            return String(format: "%@%.3f", symbol, value)
        }
    }

    private func formatRequestAxisLabel(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.1fK", value / 1000)
        }
        return String(format: "%.0f", value)
    }

    /// Compact token count formatter: 1234 -> "1.2K", 1_500_000 -> "1.5M", etc.
    private func formatTokenCount(_ count: Int) -> String {
        let thresholds: [(divisor: Double, suffix: String)] = [
            (1_000_000_000_000.0, "T"),
            (1_000_000_000.0, "G"),
            (1_000_000.0, "M"),
            (1_000.0, "K"),
        ]
        for (divisor, suffix) in thresholds {
            if Double(count) >= divisor {
                let value = Double(count) / divisor
                if value >= 100 || value == value.rounded() {
                    return "\(Int(value))\(suffix)"
                }
                return String(format: "%.1f%@", value, suffix)
            }
        }
        return "\(count)"
    }

    /// Format a Double for token axis labels (real values may exceed Int range).
    private func formatTokenAxisLabel(_ value: Double) -> String {
        if value == 0 { return "0" }
        let thresholds: [(divisor: Double, suffix: String)] = [
            (1_000_000_000_000.0, "T"),
            (1_000_000_000.0, "G"),
            (1_000_000.0, "M"),
            (1_000.0, "K"),
        ]
        for (divisor, suffix) in thresholds {
            if abs(value) >= divisor {
                let v = value / divisor
                if v >= 100 || v == v.rounded() {
                    return "\(Int(v))\(suffix)"
                }
                return String(format: "%.1f%@", v, suffix)
            }
        }
        return String(format: "%.0f", value)
    }

    private func currencySymbol(for code: String) -> String {
        switch code.uppercased() {
        case "CNY": return "¥"
        case "USD": return "$"
        case "EUR": return "€"
        case "JPY": return "¥"
        case "GBP": return "£"
        default: return code + " "
        }
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

// MARK: - Skeleton

/// Shimmering placeholder used by the loading skeleton. Renders a base
/// gray bar with a translucent gradient sweeping left-to-right, so the
/// eye reads it as "loading" rather than a static empty box. The phase
/// range (-0.5 → 1.5) keeps the gradient off-screen at both ends of the
/// loop, hiding the repeat jump.
private struct SkeletonView: View {
    let cornerRadius: CGFloat
    @State private var phase: CGFloat = -0.5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color.gray.opacity(0.15)

                LinearGradient(
                    colors: [
                        Color.gray.opacity(0.0),
                        Color.gray.opacity(0.3),
                        Color.gray.opacity(0.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geo.size.width * 0.5)
                .offset(x: phase * geo.size.width)
            }
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = 1.5
            }
        }
    }
}

#Preview {
    let sample = DeepSeekPlatformUsage(
        currency: "CNY",
        year: 2026,
        month: 5,
        dailyUsage: [
            DeepSeekDailyUsage(date: "2026-05-01", totalCost: 0, promptCacheHitCost: 0, promptCacheMissCost: 0, responseCost: 0, promptTokenCost: 0, requestCount: 0, totalTokens: 0, promptCacheHitTokens: 0, promptCacheMissTokens: 0, responseTokens: 0, promptTokens: 0, modelBreakdown: []),
            DeepSeekDailyUsage(date: "2026-05-02", totalCost: 1.5, promptCacheHitCost: 0.2, promptCacheMissCost: 0.9, responseCost: 0.4, promptTokenCost: 0, requestCount: 3, totalTokens: 120_000, promptCacheHitTokens: 80_000, promptCacheMissTokens: 25_000, responseTokens: 15_000, promptTokens: 0, modelBreakdown: []),
            DeepSeekDailyUsage(date: "2026-05-03", totalCost: 2.8, promptCacheHitCost: 0.4, promptCacheMissCost: 1.6, responseCost: 0.8, promptTokenCost: 0, requestCount: 5, totalTokens: 250_000, promptCacheHitTokens: 160_000, promptCacheMissTokens: 60_000, responseTokens: 30_000, promptTokens: 0, modelBreakdown: []),
            DeepSeekDailyUsage(date: "2026-05-04", totalCost: 1.2, promptCacheHitCost: 0.1, promptCacheMissCost: 0.7, responseCost: 0.4, promptTokenCost: 0, requestCount: 2, totalTokens: 90_000, promptCacheHitTokens: 50_000, promptCacheMissTokens: 25_000, responseTokens: 15_000, promptTokens: 0, modelBreakdown: []),
            DeepSeekDailyUsage(date: "2026-05-05", totalCost: 3.5, promptCacheHitCost: 0.5, promptCacheMissCost: 2.0, responseCost: 1.0, promptTokenCost: 0, requestCount: 8, totalTokens: 350_000, promptCacheHitTokens: 200_000, promptCacheMissTokens: 100_000, responseTokens: 50_000, promptTokens: 0, modelBreakdown: [])
        ],
        modelTotals: [
            DeepSeekModelTotalUsage(
                modelName: "deepseek-v4-pro",
                promptCacheHitCost: 0.8, promptCacheMissCost: 4.0, responseCost: 2.0, promptTokenCost: 0, totalCost: 6.8,
                promptCacheHitTokens: 490_000, promptCacheMissTokens: 210_000, responseTokens: 110_000, promptTokens: 0,
                totalTokens: 810_000, requestCount: 12),
            DeepSeekModelTotalUsage(
                modelName: "deepseek-v4-flash",
                promptCacheHitCost: 0.4, promptCacheMissCost: 1.2, responseCost: 0.6, promptTokenCost: 0, totalCost: 2.2,
                promptCacheHitTokens: 80_000, promptCacheMissTokens: 30_000, responseTokens: 15_000, promptTokens: 0,
                totalTokens: 125_000, requestCount: 6)
        ]
    )
    DeepSeekUsageView(
        usage: sample,
        balance: DeepSeekBalance(currency: "CNY", totalBalance: "50.77", grantedBalance: "0.00", toppedUpBalance: "50.77"),
        isLoading: false,
        errorMessage: nil,
        monthlyTrend: [],
        isMonthlyTrendLoading: false,
        monthlyTrendErrorMessage: nil,
        onRefresh: {},
        onMonthChange: { _, _ in }
    )
    .background(.blue.opacity(0.3))
}
