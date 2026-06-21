import Foundation

/// DeepSeek platform usage combining two platform endpoints:
/// - `/usage/cost`   → CNY monetary amounts (cost breakdown by token type)
/// - `/usage/amount` → actual token counts and request counts
///
/// Fields named `*Cost` are in account `currency` (CNY). Fields named `*Tokens`
/// and `requestCount` are real integer counts (sourced from /usage/amount).
struct DeepSeekPlatformUsage: Codable, Equatable {
    let currency: String
    let year: Int
    let month: Int
    let dailyUsage: [DeepSeekDailyUsage]
    let modelTotals: [DeepSeekModelTotalUsage]

    /// Total billed cost across the month, in `currency`.
    var totalConsumption: Double {
        dailyUsage.reduce(0) { $0 + $1.totalCost }
    }

    /// Total request count across the month.
    var totalRequests: Double {
        dailyUsage.reduce(0) { $0 + $1.requestCount }
    }

    /// Total token count (prompt + response) across the month.
    var totalTokens: Double {
        dailyUsage.reduce(0) { $0 + $1.totalTokens }
    }
}

struct DeepSeekDailyUsage: Codable, Identifiable, Equatable {
    var id: String { date }
    let date: String

    // MARK: Cost (CNY), from /usage/cost
    /// Total billed cost on this day, in `currency`.
    let totalCost: Double
    let promptCacheHitCost: Double
    let promptCacheMissCost: Double
    let responseCost: Double
    let promptTokenCost: Double

    // MARK: Token/request counts, from /usage/amount
    /// API request count on this day. 0 if not reported.
    let requestCount: Double
    /// Total tokens (prompt + response) on this day.
    let totalTokens: Double
    let promptCacheHitTokens: Double
    let promptCacheMissTokens: Double
    let responseTokens: Double
    let promptTokens: Double

    let modelBreakdown: [DeepSeekModelDayUsage]
}

struct DeepSeekModelDayUsage: Codable, Identifiable, Equatable {
    var id: String { modelName }
    let modelName: String

    // Cost (CNY), from /usage/cost
    let promptCacheHitCost: Double
    let promptCacheMissCost: Double
    let responseCost: Double
    let promptTokenCost: Double
    let totalCost: Double

    // Token/request counts, from /usage/amount
    let promptCacheHitTokens: Double
    let promptCacheMissTokens: Double
    let responseTokens: Double
    let promptTokens: Double
    let totalTokens: Double
    let requestCount: Double
}

struct DeepSeekModelTotalUsage: Codable, Identifiable, Equatable {
    var id: String { modelName }
    let modelName: String

    // Cost (CNY), from /usage/cost
    let promptCacheHitCost: Double
    let promptCacheMissCost: Double
    let responseCost: Double
    let promptTokenCost: Double
    let totalCost: Double

    // Token/request counts, from /usage/amount
    let promptCacheHitTokens: Double
    let promptCacheMissTokens: Double
    let responseTokens: Double
    let promptTokens: Double
    let totalTokens: Double
    let requestCount: Double
}