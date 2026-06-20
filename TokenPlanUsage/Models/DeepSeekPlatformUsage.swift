import Foundation

struct DeepSeekPlatformUsage: Codable, Equatable {
    let currency: String
    let year: Int
    let month: Int
    let dailyUsage: [DeepSeekDailyUsage]
    let modelTotals: [DeepSeekModelTotalUsage]

    var totalConsumption: Double {
        dailyUsage.reduce(0) { $0 + $1.totalAmount }
    }

    var totalRequests: Double {
        dailyUsage.reduce(0) { $0 + $1.requestCount }
    }
}

struct DeepSeekDailyUsage: Codable, Identifiable, Equatable {
    var id: String { date }
    let date: String
    let totalAmount: Double
    let requestCount: Double
    let cacheHitTokens: Double
    let cacheMissTokens: Double
    let outputTokens: Double
    let modelBreakdown: [DeepSeekModelDayUsage]
}

struct DeepSeekModelDayUsage: Codable, Identifiable, Equatable {
    var id: String { modelName }
    let modelName: String
    let cacheHitTokens: Double
    let cacheMissTokens: Double
    let outputTokens: Double
    let requestCount: Double
    let totalAmount: Double
}

struct DeepSeekModelTotalUsage: Codable, Identifiable, Equatable {
    var id: String { modelName }
    let modelName: String
    let cacheHitTokens: Double
    let cacheMissTokens: Double
    let outputTokens: Double
    let requestCount: Double
    let totalAmount: Double
}
