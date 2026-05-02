import Foundation

class DeepSeekProvider: TokenProvider {
    let id = "deepseek"
    let displayName = "DeepSeek"
    let defaultBaseURL = "https://api.deepseek.com"
    var urlSession: URLSession = .shared

    func fetchUsage(apiKey: String, baseURL: String?) async throws -> UsageSnapshot {
        let base = baseURL ?? defaultBaseURL
        guard let url = URL(string: "\(base)/user/balance") else {
            throw TokenProviderError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TokenProviderError.invalidResponse
        }
        if http.statusCode == 401 { throw TokenProviderError.invalidAPIKey }
        guard http.statusCode == 200 else {
            throw TokenProviderError.serverError(http.statusCode)
        }

        let resp = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)

        let currency = resp.balanceInfos?.first?.currency ?? "CNY"
        let totalBalance = resp.balanceInfos?.first?.totalBalance ?? "0.00"
        let grantedBalance = resp.balanceInfos?.first?.grantedBalance ?? "0.00"
        let toppedUpBalance = resp.balanceInfos?.first?.toppedUpBalance ?? "0.00"

        let balance = DeepSeekBalance(
            currency: currency,
            totalBalance: totalBalance,
            grantedBalance: grantedBalance,
            toppedUpBalance: toppedUpBalance
        )

        return UsageSnapshot(
            providerId: id,
            planName: "DeepSeek API",
            usedCount: 0,
            totalCount: 0,
            remainingPercent: resp.isAvailable == true ? 1.0 : 0,
            refreshTime: nil,
            fetchedAt: Date(),
            status: resp.isAvailable == true ? .normal : .error("余额不足"),
            mcpQuota: nil,
            modelQuotas: nil,
            balance: balance
        )
    }

    func fetchDistribution(apiKey: String, baseURL: String?, timeRange: TimeRange) async throws -> UsageDistribution {
        return UsageDistribution(
            providerId: id,
            windowStart: Date().addingTimeInterval(-24 * 3600),
            windowEnd: Date(),
            points: []
        )
    }
}

// MARK: - Response Models

struct DeepSeekBalanceResponse: Decodable {
    let isAvailable: Bool?
    let balanceInfos: [BalanceInfo]?

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }

    struct BalanceInfo: Decodable {
        let currency: String?
        let totalBalance: String?
        let grantedBalance: String?
        let toppedUpBalance: String?

        enum CodingKeys: String, CodingKey {
            case currency
            case totalBalance = "total_balance"
            case grantedBalance = "granted_balance"
            case toppedUpBalance = "topped_up_balance"
        }
    }
}
