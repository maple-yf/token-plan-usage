import Foundation

@Observable
class MonitorViewModel {
    var snapshot: UsageSnapshot?
    var distribution: UsageDistribution?
    var isLoading = false
    var errorMessage: String?

    private let provider: TokenProvider
    private let config: ProviderConfig
    private let sharedStore = SharedStore.shared

    init(provider: TokenProvider, config: ProviderConfig) {
        self.provider = provider
        self.config = config
        // Load cached snapshot on init
        self.snapshot = sharedStore.loadSnapshot()
        self.distribution = sharedStore.loadDistribution()
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            snapshot = try await provider.fetchUsage(apiKey: config.apiKey, baseURL: config.baseURL)
            distribution = try await provider.fetchDistribution(apiKey: config.apiKey, baseURL: config.baseURL)
            // Cache the snapshot
            sharedStore.save(snapshot: snapshot!)
        } catch TokenProviderError.invalidAPIKey {
            errorMessage = "API Key 无效，请检查设置"
            snapshot = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectProvider(_ id: String) {
        // Implementation when multiple providers supported
    }
}
