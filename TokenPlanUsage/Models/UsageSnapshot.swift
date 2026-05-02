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
    let usedCount: Int
    let totalCount: Int
    let remainingCount: Int

    var id: String { modelName }
}
