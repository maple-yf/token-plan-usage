import Foundation

@Observable
class MonitorViewModel {
    var snapshot: UsageSnapshot?
    var distribution: UsageDistribution?
    var isLoading = false
    var errorMessage: String?
    var selectedTimeRange: TimeRange = .day

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
              !config.apiKey.isEmpty else {
            snapshot = nil
            distribution = nil
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            snapshot = try await provider.fetchUsage(apiKey: config.apiKey, baseURL: config.baseURL)
            distribution = try await provider.fetchDistribution(apiKey: config.apiKey, baseURL: config.baseURL, timeRange: selectedTimeRange)
            // Cache both snapshot and distribution
            sharedStore.save(snapshot: snapshot!)
            if let distribution {
                sharedStore.save(distribution: distribution)
            }
        } catch TokenProviderError.invalidAPIKey {
            errorMessage = "API Key 无效，请检查设置"
            snapshot = nil
            distribution = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshDistribution() async {
        guard let config = KeychainService.shared.load(providerId: provider.id),
              !config.apiKey.isEmpty else { return }
        do {
            distribution = try await provider.fetchDistribution(apiKey: config.apiKey, baseURL: config.baseURL, timeRange: selectedTimeRange)
            if let distribution { sharedStore.save(distribution: distribution) }
        } catch {
            // Silently fail — snapshot is still valid
        }
    }
}
