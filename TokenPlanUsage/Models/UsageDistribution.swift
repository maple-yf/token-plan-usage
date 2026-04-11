import Foundation

struct UsageDistribution: Codable, Equatable {
    let providerId: String
    let windowStart: Date
    let windowEnd: Date
    let points: [UsagePoint]
}

struct UsagePoint: Codable, Identifiable, Equatable {
    var id: Date { time }
    let time: Date
    let count: Int
}
