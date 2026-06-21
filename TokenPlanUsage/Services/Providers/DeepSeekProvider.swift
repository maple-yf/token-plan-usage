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

        // Use /usage/amount for the trend chart so it shows real token counts
        // (REQUEST counts are small integers and not useful for a per-day trend).
        let amountResp: DeepSeekPlatformAmountResponse
        do {
            amountResp = try await fetchPlatformAmount(
                month: calendar.component(.month, from: now),
                year: calendar.component(.year, from: now),
                platformToken: platformToken,
                platformCookie: config?.platformCookie
            )
        } catch {
            return UsageDistribution(
                providerId: id,
                windowStart: windowStart,
                windowEnd: now,
                points: []
            )
        }

        guard let biz = amountResp.data?.bizData else {
            return UsageDistribution(providerId: id, windowStart: windowStart, windowEnd: now, points: [])
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current

        var points: [UsagePoint] = []
        var totalTokens = 0

        for day in biz.days ?? [] {
            guard let dateStr = day.date,
                  let date = dateFormatter.date(from: dateStr),
                  date >= windowStart, date <= now,
                  let models = day.data else { continue }

            var dayTotal: Double = 0
            for model in models {
                for item in model.usage ?? [] {
                    // Only sum token types, not REQUEST (counts differ in scale).
                    switch item.type {
                    case "PROMPT_TOKEN",
                         "PROMPT_CACHE_HIT_TOKEN",
                         "PROMPT_CACHE_MISS_TOKEN",
                         "RESPONSE_TOKEN":
                        if let amountStr = item.amount, let amount = Double(amountStr) {
                            dayTotal += amount
                        }
                    default:
                        break
                    }
                }
            }

            if dayTotal > 0 {
                points.append(UsagePoint(time: date, count: Int(dayTotal)))
                totalTokens += Int(dayTotal)
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

    // MARK: - Platform Usage (cost + amount merged)

    /// Fetches both /usage/cost (CNY) and /usage/amount (token counts) in parallel
    /// and merges them into a single DeepSeekPlatformUsage. Cost is the
    /// authoritative source for monetary fields; amount is authoritative for
    /// token/request counts. Either endpoint failing leaves the other intact.
    func fetchPlatformUsage(month: Int, year: Int) async throws -> DeepSeekPlatformUsage {
        let config = KeychainService.shared.load(providerId: id)
        guard let platformToken = config?.platformToken, !platformToken.isEmpty else {
            throw TokenProviderError.invalidAPIKey
        }
        let cookie = config?.platformCookie

        // Fetch both endpoints in parallel; tolerate failure on either side.
        async let costAsync = fetchPlatformCost(month: month, year: year, platformToken: platformToken, platformCookie: cookie)
        async let amountAsync = fetchPlatformAmount(month: month, year: year, platformToken: platformToken, platformCookie: cookie)

        let costResp: DeepSeekPlatformCostResponse?
        do {
            costResp = try await costAsync
        } catch {
            costResp = nil
        }

        let amountResp: DeepSeekPlatformAmountResponse?
        do {
            amountResp = try await amountAsync
        } catch {
            amountResp = nil
        }

        let costData = costResp?.data?.bizData?.first
        let amountData = amountResp?.data?.bizData

        if costData == nil && amountData == nil {
            throw TokenProviderError.invalidResponse
        }

        let currency = costData?.currency ?? "CNY"

        // Index amount entries by (date, modelName) for O(1) join.
        struct AmountKey: Hashable { let date: String; let model: String }
        var amountByDayModel: [AmountKey: DeepSeekAmountModelUsage] = [:]
        var amountModelTotalsByName: [String: DeepSeekModelTotal] = [:]
        if let biz = amountData {
            for day in biz.days ?? [] {
                guard let date = day.date else { continue }
                for model in day.data ?? [] {
                    guard let name = model.model else { continue }
                    amountByDayModel[AmountKey(date: date, model: name)] = model
                }
            }
            for total in biz.total ?? [] {
                guard let name = total.model else { continue }
                amountModelTotalsByName[name] = total
            }
        }

        // Build dailyUsage: one entry per date seen in either source.
        var dailyByDate: [String: DeepSeekDailyUsage] = [:]

        if let cost = costData, let days = cost.days {
            for day in days {
                guard let dateStr = day.date else { continue }
                var totalCost: Double = 0
                var requestCount: Double = 0
                var promptCacheHitCost: Double = 0
                var promptCacheMissCost: Double = 0
                var responseCost: Double = 0
                var promptTokenCost: Double = 0
                var promptCacheHitTokens: Double = 0
                var promptCacheMissTokens: Double = 0
                var responseTokens: Double = 0
                var promptTokens: Double = 0
                var totalTokens: Double = 0
                var modelBreakdown: [DeepSeekModelDayUsage] = []

                for model in day.data ?? [] {
                    let name = model.model ?? "Unknown"
                    var mCacheHitCost: Double = 0
                    var mCacheMissCost: Double = 0
                    var mResponseCost: Double = 0
                    var mPromptCost: Double = 0
                    var mTotalCost: Double = 0

                    for item in model.usage ?? [] {
                        let amount = Double(item.amount ?? "0") ?? 0
                        switch item.type {
                        case "PROMPT_CACHE_HIT_TOKEN":
                            mCacheHitCost += amount
                            promptCacheHitCost += amount
                        case "PROMPT_CACHE_MISS_TOKEN":
                            mCacheMissCost += amount
                            promptCacheMissCost += amount
                        case "RESPONSE_TOKEN":
                            mResponseCost += amount
                            responseCost += amount
                        case "PROMPT_TOKEN":
                            mPromptCost += amount
                            promptTokenCost += amount
                        default:
                            break
                        }
                        mTotalCost += amount
                        totalCost += amount
                    }

                    // Pull token/request counts from the amount endpoint for this day+model.
                    var mRequest: Double = 0
                    var mCacheHitTokens: Double = 0
                    var mCacheMissTokens: Double = 0
                    var mResponseTokens: Double = 0
                    var mPromptTokens: Double = 0
                    var mTotalTokens: Double = 0
                    if let amt = amountByDayModel[AmountKey(date: dateStr, model: name)] {
                        for item in amt.usage ?? [] {
                            let n = Double(item.amount ?? "0") ?? 0
                            switch item.type {
                            case "REQUEST":
                                mRequest += n
                                requestCount += n
                            case "PROMPT_CACHE_HIT_TOKEN":
                                mCacheHitTokens += n
                                promptCacheHitTokens += n
                            case "PROMPT_CACHE_MISS_TOKEN":
                                mCacheMissTokens += n
                                promptCacheMissTokens += n
                            case "RESPONSE_TOKEN":
                                mResponseTokens += n
                                responseTokens += n
                            case "PROMPT_TOKEN":
                                mPromptTokens += n
                                promptTokens += n
                            default:
                                break
                            }
                            mTotalTokens += n
                            totalTokens += n
                        }
                    }

                    modelBreakdown.append(DeepSeekModelDayUsage(
                        modelName: name,
                        promptCacheHitCost: mCacheHitCost,
                        promptCacheMissCost: mCacheMissCost,
                        responseCost: mResponseCost,
                        promptTokenCost: mPromptCost,
                        totalCost: mTotalCost,
                        promptCacheHitTokens: mCacheHitTokens,
                        promptCacheMissTokens: mCacheMissTokens,
                        responseTokens: mResponseTokens,
                        promptTokens: mPromptTokens,
                        totalTokens: mTotalTokens,
                        requestCount: mRequest
                    ))
                }

                dailyByDate[dateStr] = DeepSeekDailyUsage(
                    date: dateStr,
                    totalCost: totalCost,
                    promptCacheHitCost: promptCacheHitCost,
                    promptCacheMissCost: promptCacheMissCost,
                    responseCost: responseCost,
                    promptTokenCost: promptTokenCost,
                    requestCount: requestCount,
                    totalTokens: totalTokens,
                    promptCacheHitTokens: promptCacheHitTokens,
                    promptCacheMissTokens: promptCacheMissTokens,
                    responseTokens: responseTokens,
                    promptTokens: promptTokens,
                    modelBreakdown: modelBreakdown
                )
            }
        }

        // Fall back to amount-only dates (in case cost endpoint had no days).
        if let biz = amountData {
            for day in biz.days ?? [] {
                guard let dateStr = day.date, dailyByDate[dateStr] == nil else { continue }
                var requestCount: Double = 0
                var promptCacheHitTokens: Double = 0
                var promptCacheMissTokens: Double = 0
                var responseTokens: Double = 0
                var promptTokens: Double = 0
                var totalTokens: Double = 0
                var breakdown: [DeepSeekModelDayUsage] = []

                for model in day.data ?? [] {
                    let name = model.model ?? "Unknown"
                    var mReq: Double = 0
                    var mHit: Double = 0
                    var mMiss: Double = 0
                    var mResp: Double = 0
                    var mPrompt: Double = 0
                    var mTotal: Double = 0
                    for item in model.usage ?? [] {
                        let n = Double(item.amount ?? "0") ?? 0
                        switch item.type {
                        case "REQUEST":
                            mReq += n; requestCount += n
                        case "PROMPT_CACHE_HIT_TOKEN":
                            mHit += n; promptCacheHitTokens += n
                        case "PROMPT_CACHE_MISS_TOKEN":
                            mMiss += n; promptCacheMissTokens += n
                        case "RESPONSE_TOKEN":
                            mResp += n; responseTokens += n
                        case "PROMPT_TOKEN":
                            mPrompt += n; promptTokens += n
                        default: break
                        }
                        mTotal += n; totalTokens += n
                    }
                    breakdown.append(DeepSeekModelDayUsage(
                        modelName: name,
                        promptCacheHitCost: 0, promptCacheMissCost: 0, responseCost: 0,
                        promptTokenCost: 0, totalCost: 0,
                        promptCacheHitTokens: mHit, promptCacheMissTokens: mMiss,
                        responseTokens: mResp, promptTokens: mPrompt,
                        totalTokens: mTotal, requestCount: mReq
                    ))
                }

                dailyByDate[dateStr] = DeepSeekDailyUsage(
                    date: dateStr,
                    totalCost: 0,
                    promptCacheHitCost: 0, promptCacheMissCost: 0, responseCost: 0, promptTokenCost: 0,
                    requestCount: requestCount,
                    totalTokens: totalTokens,
                    promptCacheHitTokens: promptCacheHitTokens,
                    promptCacheMissTokens: promptCacheMissTokens,
                    responseTokens: responseTokens,
                    promptTokens: promptTokens,
                    modelBreakdown: breakdown
                )
            }
        }

        let dailyUsage = dailyByDate.values.sorted { $0.date < $1.date }

        // Build modelTotals: prefer cost data (has currency), enrich with amount counts.
        var modelTotals: [DeepSeekModelTotalUsage] = []
        let costTotals = costData?.total ?? []
        let amountTotals = amountData?.total ?? []
        var seenModels = Set<String>()

        for total in costTotals {
            let name = total.model ?? "Unknown"
            seenModels.insert(name)
            var promptCacheHitCost: Double = 0
            var promptCacheMissCost: Double = 0
            var responseCost: Double = 0
            var promptTokenCost: Double = 0
            var totalCost: Double = 0
            for item in total.usage ?? [] {
                let amount = Double(item.amount ?? "0") ?? 0
                switch item.type {
                case "PROMPT_CACHE_HIT_TOKEN": promptCacheHitCost += amount
                case "PROMPT_CACHE_MISS_TOKEN": promptCacheMissCost += amount
                case "RESPONSE_TOKEN": responseCost += amount
                case "PROMPT_TOKEN": promptTokenCost += amount
                default: break
                }
                totalCost += amount
            }

            var promptCacheHitTokens: Double = 0
            var promptCacheMissTokens: Double = 0
            var responseTokens: Double = 0
            var promptTokens: Double = 0
            var totalTokens: Double = 0
            var requestCount: Double = 0
            if let amt = amountModelTotalsByName[name] {
                for item in amt.usage ?? [] {
                    let n = Double(item.amount ?? "0") ?? 0
                    switch item.type {
                    case "REQUEST": requestCount += n
                    case "PROMPT_CACHE_HIT_TOKEN": promptCacheHitTokens += n
                    case "PROMPT_CACHE_MISS_TOKEN": promptCacheMissTokens += n
                    case "RESPONSE_TOKEN": responseTokens += n
                    case "PROMPT_TOKEN": promptTokens += n
                    default: break
                    }
                    totalTokens += n
                }
            }

            modelTotals.append(DeepSeekModelTotalUsage(
                modelName: name,
                promptCacheHitCost: promptCacheHitCost,
                promptCacheMissCost: promptCacheMissCost,
                responseCost: responseCost,
                promptTokenCost: promptTokenCost,
                totalCost: totalCost,
                promptCacheHitTokens: promptCacheHitTokens,
                promptCacheMissTokens: promptCacheMissTokens,
                responseTokens: responseTokens,
                promptTokens: promptTokens,
                totalTokens: totalTokens,
                requestCount: requestCount
            ))
        }

        // Append amount-only models that cost endpoint didn't know about.
        for total in amountTotals {
            let name = total.model ?? "Unknown"
            if seenModels.contains(name) { continue }
            var promptCacheHitTokens: Double = 0
            var promptCacheMissTokens: Double = 0
            var responseTokens: Double = 0
            var promptTokens: Double = 0
            var totalTokens: Double = 0
            var requestCount: Double = 0
            for item in total.usage ?? [] {
                let n = Double(item.amount ?? "0") ?? 0
                switch item.type {
                case "REQUEST": requestCount += n
                case "PROMPT_CACHE_HIT_TOKEN": promptCacheHitTokens += n
                case "PROMPT_CACHE_MISS_TOKEN": promptCacheMissTokens += n
                case "RESPONSE_TOKEN": responseTokens += n
                case "PROMPT_TOKEN": promptTokens += n
                default: break
                }
                totalTokens += n
            }
            modelTotals.append(DeepSeekModelTotalUsage(
                modelName: name,
                promptCacheHitCost: 0, promptCacheMissCost: 0, responseCost: 0,
                promptTokenCost: 0, totalCost: 0,
                promptCacheHitTokens: promptCacheHitTokens,
                promptCacheMissTokens: promptCacheMissTokens,
                responseTokens: responseTokens,
                promptTokens: promptTokens,
                totalTokens: totalTokens,
                requestCount: requestCount
            ))
        }

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

    private func fetchPlatformAmount(month: Int, year: Int, platformToken: String, platformCookie: String?) async throws -> DeepSeekPlatformAmountResponse {
        guard let url = URL(string: "https://platform.deepseek.com/api/v0/usage/amount?month=\(month)&year=\(year)") else {
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

        let resp = try JSONDecoder().decode(DeepSeekPlatformAmountResponse.self, from: data)
        return resp
    }
}

// MARK: - Balance Response

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

// MARK: - /usage/cost Response (CNY amounts, biz_data is an ARRAY)

struct DeepSeekPlatformCostResponse: Decodable {
    let code: Int?
    let data: CostDataWrapper?

    struct CostDataWrapper: Decodable {
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

// MARK: - /usage/amount Response (token counts, biz_data is an OBJECT — no currency)

struct DeepSeekPlatformAmountResponse: Decodable {
    let code: Int?
    let data: AmountDataWrapper?

    struct AmountDataWrapper: Decodable {
        let bizCode: Int?
        let bizData: DeepSeekPlatformAmountData?

        enum CodingKeys: String, CodingKey {
            case bizCode = "biz_code"
            case bizData = "biz_data"
        }
    }
}

struct DeepSeekPlatformAmountData: Decodable {
    let days: [DeepSeekDayUsage]?
    let total: [DeepSeekModelTotal]?
}

// MARK: - Shared low-level types (days[].data[].usage[], total[].usage[])

struct DeepSeekDayUsage: Decodable {
    let date: String?
    let data: [DeepSeekAmountModelUsage]?
}

struct DeepSeekAmountModelUsage: Decodable {
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