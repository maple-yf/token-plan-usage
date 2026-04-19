import Foundation

struct UsageDistribution: Codable, Equatable {
    let providerId: String
    let windowStart: Date
    let windowEnd: Date
    let points: [UsagePoint]
    var totalTokens: Int? = nil
}

struct UsagePoint: Codable, Identifiable, Equatable {
    var id: Date { time }
    let time: Date
    let count: Int
}

enum TimeRange: String, CaseIterable, Identifiable {
    case day = "24小时"
    case week = "一周"
    case month = "一个月"

    var id: String { rawValue }

    /// Number of days to look back
    var days: Int {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        }
    }
}
