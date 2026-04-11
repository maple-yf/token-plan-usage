import Foundation

class MiniMaxProvider: TokenProvider {
    let id = "minimax"
    let displayName = "MiniMax"
    let defaultBaseURL = "https://api.minimax.chat"
    var urlSession: URLSession = .shared

    func fetchUsage(apiKey: String, baseURL: String?) async throws -> UsageSnapshot {
        let base = baseURL ?? defaultBaseURL
        guard let url = URL(string: "\(base)/v1/user/info") else {
            throw TokenProviderError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
        struct Response: Decodable {
            let data: UsageData?
            struct UsageData: Decodable {
                let total: Int
                let used: Int
                let planName: String?
                enum CodingKeys: String, CodingKey {
                    case total, used
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
        guard let usage = resp.data else { throw TokenProviderError.invalidResponse }
        let remaining = usage.total - usage.used
        let percent = usage.total > 0 ? Double(remaining) / Double(usage.total) : 0
        return UsageSnapshot(
            providerId: id,
            planName: usage.planName ?? "MiniMax",
            usedCount: usage.used,
            totalCount: usage.total,
            remainingPercent: percent,
            refreshTime: nil,
            fetchedAt: Date(),
            status: .normal
        )
    }
}
