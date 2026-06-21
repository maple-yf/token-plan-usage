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
