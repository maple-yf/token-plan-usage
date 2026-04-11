import Foundation

protocol TokenProvider {
    var id: String { get }
    var displayName: String { get }
    var defaultBaseURL: String { get }

    func fetchUsage(apiKey: String, baseURL: String?) async throws -> UsageSnapshot
    func fetchDistribution(apiKey: String, baseURL: String?) async throws -> UsageDistribution
}

enum TokenProviderError: LocalizedError {
    case invalidAPIKey
    case networkUnavailable
    case serverError(Int)
    case invalidResponse
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey: return "API Key 无效，请检查设置"
        case .networkUnavailable: return "网络不可用"
        case .serverError(let code): return "服务端错误 (\(code))"
        case .invalidResponse: return "响应格式异常"
        case .timeout: return "请求超时"
        }
    }
}
