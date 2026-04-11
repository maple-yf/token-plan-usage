import Foundation

class GLMProvider: TokenProvider {
    let id = "glm"
    let displayName = "GLM（智谱）"
    let defaultBaseURL = "https://open.bigmodel.cn/api/paas/v4"
    var urlSession: URLSession = .shared

    func fetchUsage(apiKey: String, baseURL: String?) async throws -> UsageSnapshot {
        let base = baseURL ?? defaultBaseURL
        guard let url = URL(string: "\(base)/users/balance") else {
            throw TokenProviderError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TokenProviderError.invalidResponse
        }
        if http.statusCode == 401 { throw TokenProviderError.invalidAPIKey }
        guard http.statusCode == 200 else {
            throw TokenProviderError.serverError(http.statusCode)
        }
        return try parseUsageResponse(data)
    }

    func fetchDistribution(apiKey: String, baseURL: String?) async throws -> UsageDistribution {
        return UsageDistribution(
            providerId: id,
            windowStart: Date().addingTimeInterval(-5 * 3600),
            windowEnd: Date(),
            points: []
        )
    }

    private func parseUsageResponse(_ data: Data) throws -> UsageSnapshot {
        // 智谱 balance API response format (estimated — to be confirmed)
        struct Response: Decodable {
            let data: BalanceData?
            struct BalanceData: Decodable {
                let totalTokens: Int?
                let usedTokens: Int?
                let remainingTokens: Int?
                let planName: String?
                enum CodingKeys: String, CodingKey {
                    case totalTokens = "total_tokens"
                    case usedTokens = "used_tokens"
                    case remainingTokens = "remaining_tokens"
                    case planName = "plan_name"
                }
            }
        }
        let resp: Response
        do {
            resp = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw TokenProviderError.invalidResponse
        }
        guard let balance = resp.data,
              let total = balance.totalTokens,
              let used = balance.usedTokens else {
            throw TokenProviderError.invalidResponse
        }
        let remaining = total - used
        let percent = total > 0 ? Double(remaining) / Double(total) : 0
        return UsageSnapshot(
            providerId: id,
            planName: balance.planName ?? "GLM",
            usedCount: used,
            totalCount: total,
            remainingPercent: percent,
            refreshTime: nil,
            fetchedAt: Date(),
            status: .normal
        )
    }
}
