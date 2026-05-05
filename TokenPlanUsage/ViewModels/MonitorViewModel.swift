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

    private let provider: TokenProvider
    private let sharedStore = SharedStore.shared

    init(provider: TokenProvider, config: ProviderConfig) {
        self.provider = provider
        // Load cached snapshot on init
        self.snapshot = sharedStore.loadSnapshot(providerId: provider.id)
        self.distribution = sharedStore.loadDistribution(providerId: provider.id)
    }

    func refresh() async {
        // Reload config from Keychain to pick up any changes made in Settings
        guard let config = KeychainService.shared.load(providerId: provider.id),
              !config.apiKey.isEmpty || !(config.platformToken?.isEmpty ?? true) else {
            snapshot = nil
            distribution = nil
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Fetch usage snapshot (requires API key)
        if !config.apiKey.isEmpty {
            do {
                snapshot = try await provider.fetchUsage(apiKey: config.apiKey, baseURL: config.baseURL)
                sharedStore.save(snapshot: snapshot!)
            } catch TokenProviderError.invalidAPIKey {
                errorMessage = "API Key 无效，请检查设置"
                snapshot = nil
            } catch {
                // Balance fetch failure is non-fatal if platform token is available
                if config.platformToken?.isEmpty ?? true {
                    errorMessage = error.localizedDescription
                }
            }
        }

        // Fetch distribution (may use platformToken internally for some providers)
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
}
