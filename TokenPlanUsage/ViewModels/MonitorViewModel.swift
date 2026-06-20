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
        }
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
