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
        // MiniMax API does not provide historical distribution data.
        // The trend chart is hidden for MiniMax in MonitorView (see docs).
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

            /// MiniMax coding_plan remains entry. The real API returns percentage-based
            /// quotas, not raw counts. Field semantics (see docs/plans):
            /// - current_interval_remaining_percent: 5-hour interval remaining percent (0-100)
            /// - current_weekly_status: weekly quota status; 3 = unlimited
            /// - current_weekly_remaining_percent: weekly remaining percent (0-100)
            /// - remains_time: milliseconds until the 5-hour interval refresh
            struct ModelRemain: Decodable {
                let modelName: String?
                let currentIntervalRemainingPercent: Double?
                let currentWeeklyStatus: Int?
                let currentWeeklyRemainingPercent: Double?
                let remainsTime: TimeInterval?

                enum CodingKeys: String, CodingKey {
                    case modelName = "model_name"
                    case currentIntervalRemainingPercent = "current_interval_remaining_percent"
                    case currentWeeklyStatus = "current_weekly_status"
                    case currentWeeklyRemainingPercent = "current_weekly_remaining_percent"
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

        guard let remains = resp.modelRemains, !remains.isEmpty else {
            throw TokenProviderError.invalidResponse
        }

        // Prefer MiniMax-M* model, fall back to first entry
        let mainModel = remains.first(where: { $0.modelName?.hasPrefix("MiniMax-M") ?? false })
            ?? remains.first!

        // Real API is percentage-based. usedCount/totalCount are set to 0 so views
        // enter "percentage mode" (isPercentageMode). remainingPercent is a 0-1 ratio.
        let intervalRemainingPercent = max(0, min(100, mainModel.currentIntervalRemainingPercent ?? 0))
        let remainingRatio = intervalRemainingPercent / 100.0

        // remains_time is the milliseconds until the 5-hour interval refresh.
        // Treat it as the refresh/reset timestamp = now + remains_time.
        let refreshTime: Date? = mainModel.remainsTime.map { remainsMs -> Date in
            // remains_time is a *duration* in ms until refresh, not an absolute timestamp.
            return Date().addingTimeInterval(remainsMs / 1000.0)
        }

        return UsageSnapshot(
            providerId: id,
            planName: mainModel.modelName ?? "MiniMax",
            usedCount: 0,
            totalCount: 0,
            remainingPercent: remainingRatio,
            refreshTime: refreshTime,
            fetchedAt: Date(),
            status: .normal,
            mcpQuota: nil,
            modelQuotas: remains.compactMap { model in
                guard let name = model.modelName else { return nil }
                return MiniMaxModelQuota(
                    modelName: name,
                    intervalRemainingPercent: model.currentIntervalRemainingPercent ?? 0,
                    weeklyStatus: model.currentWeeklyStatus,
                    weeklyRemainingPercent: model.currentWeeklyRemainingPercent
                )
            }
        )
    }
}
