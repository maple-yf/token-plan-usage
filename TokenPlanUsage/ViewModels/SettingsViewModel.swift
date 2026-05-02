import Foundation

@Observable
class SettingsViewModel {
    var providers: [ProviderConfig] = [
        ProviderConfig.minimax,
        ProviderConfig.glm,
        ProviderConfig.deepseek
    ]
    var refreshInterval: TimeInterval = 5 * 60 // 5 minutes
    var widgetProvider: String = "minimax"
    var baseURLValidationError: String?

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
        if let deepseek = keychainService.load(providerId: "deepseek") {
            providers[2] = deepseek
        }
    }

    func updateProvider(_ config: ProviderConfig) throws {
        // Validate base URL before saving
        if let baseURL = config.baseURL, !baseURL.isEmpty {
            guard validateBaseURL(baseURL) else {
                throw SettingsError.invalidBaseURL
            }
        }
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
        baseURLValidationError = nil
        guard let urlString = urlString, !urlString.isEmpty else { return true } // nil/empty = default = valid
        guard urlString.hasPrefix("https://") else {
            baseURLValidationError = "Base URL 必须以 https:// 开头"
            return false
        }
        guard let url = URL(string: urlString),
              let host = url.host,
              !host.isEmpty else {
            baseURLValidationError = "URL 格式无效"
            return false
        }
        return true
    }

    enum SettingsError: LocalizedError {
        case invalidBaseURL

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL: return "Base URL 格式无效，必须以 https:// 开头且为合法 URL"
            }
        }
    }
}
