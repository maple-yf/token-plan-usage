import Foundation

@Observable
class MonitorViewModel {
    var snapshot: UsageSnapshot?
    var distribution: UsageDistribution?
    var isLoading = false
    var errorMessage: String?
    var selectedTimeRange: TimeRange = .day
    var isDistributionLoading = false
    var distributionErrorMessage: String?

    var platformUsage: DeepSeekPlatformUsage?
    var isPlatformUsageLoading = false
    var platformUsageErrorMessage: String?

    /// Past-6-month consumption trend for the DeepSeek chart. Empty when
    /// unavailable (no token, or all month fetches failed).
    var monthlyTrend: [MonthlyConsumptionPoint] = []
    var isMonthlyTrendLoading = false
    var monthlyTrendErrorMessage: String?

    private let provider: TokenProvider
    private let sharedStore = SharedStore.shared

    init(provider: TokenProvider, config: ProviderConfig) {
        self.provider = provider
        self.snapshot = sharedStore.loadSnapshot(providerId: provider.id)
        self.distribution = sharedStore.loadDistribution(providerId: provider.id)
    }

    func refresh() async {
        guard let config = KeychainService.shared.load(providerId: provider.id),
              !config.apiKey.isEmpty || !(config.platformToken?.isEmpty ?? true) else {
            snapshot = nil
            distribution = nil
            platformUsage = nil
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if !config.apiKey.isEmpty {
            do {
                snapshot = try await provider.fetchUsage(apiKey: config.apiKey, baseURL: config.baseURL)
                sharedStore.save(snapshot: snapshot!)
            } catch TokenProviderError.invalidAPIKey {
                errorMessage = "API Key 无效，请检查设置"
                snapshot = nil
            } catch {
                if config.platformToken?.isEmpty ?? true {
                    errorMessage = error.localizedDescription
                }
            }
        }

        do {
            distribution = try await provider.fetchDistribution(apiKey: config.apiKey, baseURL: config.baseURL, timeRange: selectedTimeRange)
            if let distribution {
                sharedStore.save(distribution: distribution)
            }
        } catch {
            if errorMessage == nil {
                errorMessage = error.localizedDescription
            }
        }

        if provider.id == "deepseek", let pt = config.platformToken, !pt.isEmpty {
            await refreshPlatformUsage()
            await refreshMonthlyTrend()
        }
    }

    /// Fetches the past 6 months of total consumption in parallel (one
    /// /usage/cost + /usage/amount per month, dispatched via TaskGroup).
    /// Months that fail to load are silently skipped — a partial trend is
    /// more useful than an empty chart.
    func refreshMonthlyTrend(monthsBack: Int = 5) async {
        guard let deepseekProvider = provider as? DeepSeekProvider else { return }
        guard let config = KeychainService.shared.load(providerId: provider.id),
              let platformToken = config.platformToken, !platformToken.isEmpty else {
            monthlyTrend = []
            monthlyTrendErrorMessage = nil
            return
        }

        isMonthlyTrendLoading = true
        monthlyTrendErrorMessage = nil

        let calendar = Calendar.current
        let now = Date()
        var collected: [(Date, Double, String)] = []

        await withTaskGroup(of: (Int, Int, Double?, String?).self) { group in
            for offset in (0...monthsBack).reversed() {
                guard let monthDate = calendar.date(byAdding: .month, value: -offset, to: now) else { continue }
                let month = calendar.component(.month, from: monthDate)
                let year = calendar.component(.year, from: monthDate)
                group.addTask {
                    do {
                        let usage = try await deepseekProvider.fetchPlatformUsage(month: month, year: year)
                        return (usage.year, usage.month, usage.totalConsumption, usage.currency)
                    } catch {
                        return (year, month, nil, nil)
                    }
                }
            }

            for await (year, month, consumption, currency) in group {
                guard let consumption, let currency else { continue }
                let monthDate = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
                collected.append((monthDate, consumption, currency))
            }
        }

        collected.sort { $0.0 < $1.0 }
        monthlyTrend = collected.map { MonthlyConsumptionPoint(month: $0.0, consumption: $0.1, currency: $0.2) }
        isMonthlyTrendLoading = false
    }

    func refreshDistribution() async {
        guard let config = KeychainService.shared.load(providerId: provider.id),
              !config.apiKey.isEmpty || !(config.platformToken?.isEmpty ?? true) else { return }
        isDistributionLoading = true
        distributionErrorMessage = nil
        defer { isDistributionLoading = false }
        do {
            distribution = try await provider.fetchDistribution(apiKey: config.apiKey, baseURL: config.baseURL, timeRange: selectedTimeRange)
            if let distribution { sharedStore.save(distribution: distribution) }
        } catch {
            distributionErrorMessage = error.localizedDescription
        }
    }

    func refreshPlatformUsage(month: Int? = nil, year: Int? = nil) async {
        guard let deepseekProvider = provider as? DeepSeekProvider else { return }

        let calendar = Calendar.current
        let now = Date()
        let m = month ?? calendar.component(.month, from: now)
        let y = year ?? calendar.component(.year, from: now)

        isPlatformUsageLoading = true
        platformUsageErrorMessage = nil
        defer { isPlatformUsageLoading = false }

        do {
            platformUsage = try await deepseekProvider.fetchPlatformUsage(month: m, year: y)
        } catch {
            platformUsageErrorMessage = error.localizedDescription
        }
    }

    func onPlatformMonthChanged(month: Int, year: Int) {
        Task { await refreshPlatformUsage(month: month, year: year) }
    }
}
