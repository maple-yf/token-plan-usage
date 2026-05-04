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
        let now = Date()
        let calendar = Calendar.current
        let windowStart = calendar.date(byAdding: .day, value: -timeRange.days, to: now) ?? now

        // Load config to check for platform token
        let config = KeychainService.shared.load(providerId: id)
        guard let platformToken = config?.platformToken, !platformToken.isEmpty else {
            return UsageDistribution(
                providerId: id,
                windowStart: windowStart,
                windowEnd: now,
                points: []
            )
        }

        let platformCookie = config?.platformCookie

        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)
        let costResp = try await fetchPlatformCost(month: month, year: year, platformToken: platformToken, platformCookie: platformCookie)

        guard let bizData = costResp.bizData, !bizData.isEmpty else {
            return UsageDistribution(providerId: id, windowStart: windowStart, windowEnd: now, points: [])
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current

        var points: [UsagePoint] = []
        var totalTokens = 0

        for data in bizData {
            guard let days = data.days else { continue }
            for day in days {
                guard let dateStr = day.date,
                      let date = dateFormatter.date(from: dateStr),
                      date >= windowStart, date <= now,
                      let models = day.data else { continue }

                // Sum all model usage amounts for this day (convert yuan to fen)
                var dayTotal: Double = 0
                for model in models {
                    if let items = model.usage {
                        for item in items {
                            if let amountStr = item.amount, let amount = Double(amountStr) {
                                dayTotal += amount
                            }
                        }
                    }
                }

                // Skip days with zero usage
                if dayTotal > 0 {
                    let amountInFen = Int(dayTotal * 100)
                    points.append(UsagePoint(time: date, count: amountInFen))
                    totalTokens += amountInFen
                }
            }
        }

        points.sort { $0.time < $1.time }

        return UsageDistribution(
            providerId: id,
            windowStart: windowStart,
            windowEnd: now,
            points: points,
            totalTokens: totalTokens
        )
    }

    // MARK: - Private

    private func fetchPlatformCost(month: Int, year: Int, platformToken: String, platformCookie: String?) async throws -> DeepSeekPlatformCostResponse {
        guard let url = URL(string: "https://platform.deepseek.com/api/v0/usage/cost?month=\(month)&year=\(year)") else {
            throw TokenProviderError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(platformToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let cookie = platformCookie, !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        request.timeoutInterval = 15

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TokenProviderError.invalidResponse
        }
        if http.statusCode == 401 { throw TokenProviderError.invalidAPIKey }
        guard http.statusCode == 200 else {
            throw TokenProviderError.serverError(http.statusCode)
        }

        let resp = try JSONDecoder().decode(DeepSeekPlatformCostResponse.self, from: data)
        return resp
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

// MARK: - Platform API Response Models (for usage/cost)

struct DeepSeekPlatformCostResponse: Decodable {
    let bizData: [DeepSeekPlatformCostData]?

    enum CodingKeys: String, CodingKey {
        case bizData = "biz_data"
    }
}

struct DeepSeekPlatformCostData: Decodable {
    let currency: String?
    let days: [DeepSeekDayUsage]?
    let total: [DeepSeekModelTotal]?
}

struct DeepSeekDayUsage: Decodable {
    let date: String?
    let data: [DeepSeekModelUsage]?
}

struct DeepSeekModelUsage: Decodable {
    let model: String?
    let usage: [DeepSeekUsageItem]?
}

struct DeepSeekUsageItem: Decodable {
    let amount: String?
    let unit: String?
}

struct DeepSeekModelTotal: Decodable {
    let model: String?
    let usage: [DeepSeekUsageItem]?
}
