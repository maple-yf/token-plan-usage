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

        guard let bizData = costResp.data?.bizData, !bizData.isEmpty else {
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

    // MARK: - Platform Usage (rich data)

    func fetchPlatformUsage(month: Int, year: Int) async throws -> DeepSeekPlatformUsage {
        let config = KeychainService.shared.load(providerId: id)
        guard let platformToken = config?.platformToken, !platformToken.isEmpty else {
            throw TokenProviderError.invalidAPIKey
        }

        let costResp = try await fetchPlatformCost(month: month, year: year, platformToken: platformToken, platformCookie: config?.platformCookie)

        guard let bizData = costResp.data?.bizData, let firstData = bizData.first else {
            throw TokenProviderError.invalidResponse
        }

        let currency = firstData.currency ?? "CNY"
        var dailyUsage: [DeepSeekDailyUsage] = []
        var modelTotals: [DeepSeekModelTotalUsage] = []

        // Parse daily data
        if let days = firstData.days {
            for day in days {
                guard let dateStr = day.date, let models = day.data else { continue }

                var totalAmount: Double = 0
                var requestCount: Double = 0
                var cacheHitTokens: Double = 0
                var cacheMissTokens: Double = 0
                var outputTokens: Double = 0
                var modelBreakdown: [DeepSeekModelDayUsage] = []

                for model in models {
                    let modelName = model.model ?? "Unknown"
                    var mCacheHit: Double = 0
                    var mCacheMiss: Double = 0
                    var mOutput: Double = 0
                    var mRequest: Double = 0
                    var mTotal: Double = 0

                    if let items = model.usage {
                        for item in items {
                            let amount = Double(item.amount ?? "0") ?? 0
                            switch item.type {
                            case "PROMPT_CACHE_HIT_TOKEN":
                                mCacheHit += amount
                                cacheHitTokens += amount
                            case "PROMPT_CACHE_MISS_TOKEN":
                                mCacheMiss += amount
                                cacheMissTokens += amount
                            case "RESPONSE_TOKEN":
                                mOutput += amount
                                outputTokens += amount
                            case "REQUEST":
                                mRequest += amount
                                requestCount += amount
                            default:
                                break
                            }
                            mTotal += amount
                            totalAmount += amount
                        }
                    }

                    modelBreakdown.append(DeepSeekModelDayUsage(
                        modelName: modelName,
                        cacheHitTokens: mCacheHit,
                        cacheMissTokens: mCacheMiss,
                        outputTokens: mOutput,
                        requestCount: mRequest,
                        totalAmount: mTotal
                    ))
                }

                dailyUsage.append(DeepSeekDailyUsage(
                    date: dateStr,
                    totalAmount: totalAmount,
                    requestCount: requestCount,
                    cacheHitTokens: cacheHitTokens,
                    cacheMissTokens: cacheMissTokens,
                    outputTokens: outputTokens,
                    modelBreakdown: modelBreakdown
                ))
            }
        }

        // Parse model totals
        if let totals = firstData.total {
            for modelTotal in totals {
                let modelName = modelTotal.model ?? "Unknown"
                var tCacheHit: Double = 0
                var tCacheMiss: Double = 0
                var tOutput: Double = 0
                var tRequest: Double = 0
                var tTotal: Double = 0

                if let items = modelTotal.usage {
                    for item in items {
                        let amount = Double(item.amount ?? "0") ?? 0
                        switch item.type {
                        case "PROMPT_CACHE_HIT_TOKEN":
                            tCacheHit += amount
                        case "PROMPT_CACHE_MISS_TOKEN":
                            tCacheMiss += amount
                        case "RESPONSE_TOKEN":
                            tOutput += amount
                        case "REQUEST":
                            tRequest += amount
                        default:
                            break
                        }
                        tTotal += amount
                    }
                }

                modelTotals.append(DeepSeekModelTotalUsage(
                    modelName: modelName,
                    cacheHitTokens: tCacheHit,
                    cacheMissTokens: tCacheMiss,
                    outputTokens: tOutput,
                    requestCount: tRequest,
                    totalAmount: tTotal
                ))
            }
        }

        dailyUsage.sort { $0.date < $1.date }

        return DeepSeekPlatformUsage(
            currency: currency,
            year: year,
            month: month,
            dailyUsage: dailyUsage,
            modelTotals: modelTotals
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
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
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

// MARK: - Platform API Response Models

struct DeepSeekPlatformCostResponse: Decodable {
    let code: Int?
    let data: DataWrapper?

    struct DataWrapper: Decodable {
        let bizCode: Int?
        let bizData: [DeepSeekPlatformCostData]?

        enum CodingKeys: String, CodingKey {
            case bizCode = "biz_code"
            case bizData = "biz_data"
        }
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
    let type: String?
}

struct DeepSeekModelTotal: Decodable {
    let model: String?
    let usage: [DeepSeekUsageItem]?
}
