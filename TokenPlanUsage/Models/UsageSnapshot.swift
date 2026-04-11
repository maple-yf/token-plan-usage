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
}
