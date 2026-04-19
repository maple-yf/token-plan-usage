import Foundation

class MiniMaxProvider: TokenProvider {
    let id = "minimax"
    let displayName = "MiniMax"
    let defaultBaseURL = "https://www.minimaxi.com"
    var urlSession: URLSession = .shared

    func fetchUsage(apiKey: String, baseURL: String?) async throws -> UsageSnapshot {
        let base = baseURL ?? defaultBaseURL
        guard let url = URL(string: "\(base)/v1/api/openplatform/coding_plan/remains") else {
            throw TokenProviderError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TokenProviderError.invalidResponse
        }
        if http.statusCode == 401 { throw TokenProviderError.invalidAPIKey }
        guard http.statusCode == 200 else {
            throw TokenProviderError.serverError(http.statusCode)
        }
        return try parseUsageResponse(data)
    }

    func fetchDistribution(apiKey: String, baseURL: String?, timeRange: TimeRange) async throws -> UsageDistribution {
        // MiniMax API does not provide historical distribution data
        return UsageDistribution(
            providerId: id,
            windowStart: Date().addingTimeInterval(-5 * 3600),
            windowEnd: Date(),
            points: []
        )
    }

    private func parseUsageResponse(_ data: Data) throws -> UsageSnapshot {
        struct Response: Decodable {
            let modelRemains: [ModelRemain]?
            let baseResp: BaseResp?

            enum CodingKeys: String, CodingKey {
                case modelRemains = "model_remains"
                case baseResp = "base_resp"
            }

            struct ModelRemain: Decodable {
                let modelName: String
                let currentIntervalTotalCount: Int
                let currentIntervalUsageCount: Int
                let startTime: TimeInterval?
                let endTime: TimeInterval?
                let remainsTime: TimeInterval?

                enum CodingKeys: String, CodingKey {
                    case modelName = "model_name"
                    case currentIntervalTotalCount = "current_interval_total_count"
                    case currentIntervalUsageCount = "current_interval_usage_count"
                    case startTime = "start_time"
                    case endTime = "end_time"
                    case remainsTime = "remains_time"
                }
            }

            struct BaseResp: Decodable {
                let statusCode: Int?
                let statusMsg: String?

                enum CodingKeys: String, CodingKey {
                    case statusCode = "status_code"
                    case statusMsg = "status_msg"
                }
            }
        }

        let resp: Response
        do {
            resp = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw TokenProviderError.invalidResponse
        }

        // Check base_resp for errors
        if let statusCode = resp.baseResp?.statusCode, statusCode != 0 {
            let msg = resp.baseResp?.statusMsg ?? "unknown"
            throw TokenProviderError.serverError(statusCode)
        }

        // Find the main text model (MiniMax-M*) entry
        guard let remains = resp.modelRemains, !remains.isEmpty else {
            throw TokenProviderError.invalidResponse
        }

        // Prefer MiniMax-M* model, fall back to first entry
        let mainModel = remains.first(where: { $0.modelName.hasPrefix("MiniMax-M") })
            ?? remains.first!

        let remainingCount = mainModel.currentIntervalUsageCount
        let totalCount = mainModel.currentIntervalTotalCount
        let usedCount = max(totalCount - remainingCount, 0)
        let percent = totalCount > 0 ? Double(remainingCount) / Double(totalCount) : 0

        // end_time is in milliseconds
        let refreshTime = mainModel.endTime.map { Date(timeIntervalSince1970: $0 / 1000) }

        return UsageSnapshot(
            providerId: id,
            planName: mainModel.modelName,
            usedCount: usedCount,
            totalCount: totalCount,
            remainingPercent: percent,
            refreshTime: refreshTime,
            fetchedAt: Date(),
            status: .normal,
            mcpQuota: nil,
            modelQuotas: remains.map { model in
                let remaining = model.currentIntervalUsageCount
                let total = model.currentIntervalTotalCount
                let used = max(total - remaining, 0)
                return MiniMaxModelQuota(
                    modelName: model.modelName,
                    usedCount: used,
                    totalCount: total,
                    remainingCount: remaining
                )
            }.sorted { $0.totalCount > $1.totalCount }
        )
    }
}
