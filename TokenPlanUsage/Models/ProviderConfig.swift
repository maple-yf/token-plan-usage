import Foundation

struct ProviderConfig: Codable, Identifiable, Equatable {
    let id: String
    var apiKey: String
    var baseURL: String?
    var isEnabled: Bool

    static let minimax = ProviderConfig(id: "minimax", apiKey: "", baseURL: nil, isEnabled: true)
    static let glm = ProviderConfig(id: "glm", apiKey: "", baseURL: nil, isEnabled: false)
    static let deepseek = ProviderConfig(id: "deepseek", apiKey: "", baseURL: nil, isEnabled: false)
}
