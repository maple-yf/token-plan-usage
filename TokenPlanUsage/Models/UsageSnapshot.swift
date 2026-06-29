import Foundation

struct UsageSnapshot: Codable, Equatable {
    let providerId: String
    let planName: String
    let usedCount: Int
    let totalCount: Int
    let remainingPercent: Double
    let refreshTime: Date?
    let fetchedAt: Date
    let status: APIStatus
    let mcpQuota: MCPQuota?
    let modelQuotas: [MiniMaxModelQuota]?
    var balance: DeepSeekBalance? = nil
    var glmBalance: GLMBalance? = nil
}

struct DeepSeekBalance: Codable, Equatable {
    let currency: String
    let totalBalance: String
    let grantedBalance: String
    let toppedUpBalance: String
}

struct MCPQuota: Codable, Equatable {
    let usedCount: Int
    let totalCount: Int
    let remainingCount: Int
}

/// GLM (智谱) non-Coding Plan account balance snapshot. Fetched from
/// `/api/biz/account/query-customer-account-report` so the user can see
/// the actual money state of their GLM account, independent of any
/// Coding Plan subscription.
///
/// All amount fields are in `currency` (always CNY for Zhipu; the
/// endpoint doesn't echo the currency so the provider hardcodes it).
/// `todaySpendAmount` is nil when the account hasn't spent today or
/// the field isn't populated server-side.
struct GLMBalance: Codable, Equatable {
    let currency: String
    /// Available balance right now (a.k.a. `availableBalance` / `balance`).
    let balance: Double
    /// Amount currently frozen (e.g. pending settlement). Usually 0.
    let frozenBalance: Double
    /// Cumulative spend across the lifetime of the account.
    let totalSpendAmount: Double
    /// Spend since 00:00 local today. `nil` when the field is absent
    /// or the user hasn't spent today.
    let todaySpendAmount: Double?
    /// Cumulative top-ups (real money, not gifts).
    let rechargeAmount: Double
    /// Cumulative system gifts / promotional credits.
    let giveAmount: Double
}

struct MiniMaxModelQuota: Codable, Equatable, Identifiable {
    let modelName: String
    /// 5-hour interval remaining percent (0-100)
    let intervalRemainingPercent: Double
    /// Weekly quota status; nil if unknown. 3 = unlimited.
    let weeklyStatus: Int?
    /// Weekly remaining percent (0-100); nil if unknown or unlimited.
    let weeklyRemainingPercent: Double?

    var id: String { modelName }

    /// True when the weekly quota is unlimited (status == 3).
    var isWeeklyUnlimited: Bool { weeklyStatus == 3 }

    /// Used percent for the 5-hour interval (0-100).
    var intervalUsedPercent: Double { max(0, min(100, 100 - intervalRemainingPercent)) }
}
