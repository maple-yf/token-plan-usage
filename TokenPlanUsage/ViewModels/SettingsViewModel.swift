import Foundation

@Observable
class SettingsViewModel {
    var providers: [ProviderConfig] = [
        ProviderConfig.minimax,
        ProviderConfig.glm
    ]
    var refreshInterval: TimeInterval = 5 * 60 // 5 minutes
    var widgetProvider: String = "minimax"

    private let keychainService = KeychainService.shared
    private let sharedStore = SharedStore.shared

    init() {
        loadSavedConfigs()
    }

    func loadSavedConfigs() {
        if let minimax = keychainService.load(providerId: "minimax") {
            providers[0] = minimax
        }
        if let glm = keychainService.load(providerId: "glm") {
            providers[1] = glm
        }
    }

    func updateProvider(_ config: ProviderConfig) throws {
        try keychainService.save(config)
        let index = providers.firstIndex { $0.id == config.id }
        if let idx = index {
            providers[idx] = config
        }
    }

    func toggleProvider(_ id: String) throws {
        if let idx = providers.firstIndex(where: { $0.id == id }) {
            providers[idx].isEnabled.toggle()
            try keychainService.save(providers[idx])
        }
    }

    func validateBaseURL(_ urlString: String?) -> Bool {
        guard let urlString = urlString, !urlString.isEmpty else { return true }
        guard let url = URL(string: urlString) else { return false }
        return url.scheme == "https"
    }
}
