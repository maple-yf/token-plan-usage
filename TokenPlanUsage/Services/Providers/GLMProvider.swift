import Foundation

class GLMProvider: TokenProvider {
    let id = "glm"
    let displayName = "GLM（智谱）"
    let defaultBaseURL = "https://api.z.ai"
    var urlSession: URLSession = .shared

    /// Cached distribution extracted from fetchUsage's model-usage response
    private var cachedDistribution: UsageDistribution?

    func fetchUsage(apiKey: String, baseURL: String?) async throws -> UsageSnapshot {
        let base = baseURL ?? defaultBaseURL

        // Fetch model usage only — quota is fetched separately in Settings and not
        // needed for the Monitor tab's core functionality (snapshot + distribution).
        let modelUsage = try await fetchModelUsage(base: base, apiKey: apiKey)

        // Extract data from model usage
        let totalUsage = modelUsage.data?.totalUsage

        // TOKENS_LIMIT and TIME_LIMIT: fetched separately via fetchQuotaLimit (not in fetchUsage)
        let tokensPercentage = 0
        let nextResetTime: Date? = nil
        let mcpQuota: MCPQuota? = nil

        // Build plan name from models
        let modelNames = totalUsage?.modelSummaryList?.map { $0.modelName ?? "" }.joined(separator: " + ") ?? "GLM"

        // Cache distribution from the same model-usage response (avoid redundant API call)
        let now = Date()
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        cachedDistribution = buildDistribution(from: modelUsage, windowStart: startDate, windowEnd: now)

        return UsageSnapshot(
            providerId: id,
            planName: "GLM Coding Plan (\(modelNames))",
            usedCount: 0,
            totalCount: 0,
            remainingPercent: Double(100 - tokensPercentage) / 100.0,
            refreshTime: nextResetTime,
            fetchedAt: Date(),
            status: .normal,
            mcpQuota: mcpQuota,
            modelQuotas: nil
        )
    }

    func fetchDistribution(apiKey: String, baseURL: String?, timeRange: TimeRange = .day) async throws -> UsageDistribution {
        // Use cached distribution from fetchUsage if available (only matches 24h)
        if timeRange == .day, let cached = cachedDistribution { return cached }

        // Otherwise fetch independently
        let base = baseURL ?? defaultBaseURL
        let modelUsage = try await fetchModelUsage(base: base, apiKey: apiKey, timeRange: timeRange)

        let now = Date()
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -timeRange.days, to: now) ?? now

        return buildDistribution(from: modelUsage, windowStart: startDate, windowEnd: now)
    }

    // MARK: - Private

    private func fetchModelUsage(base: String, apiKey: String, timeRange: TimeRange = .day) async throws -> GLMModelUsageResponse {
        let now = Date()
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -timeRange.days, to: now) ?? now

        let startTime = formatDate(startDate)
        let endTime = formatDate(now)

        guard let url = URL(string: "\(base)/api/monitor/usage/model-usage?startTime=\(startTime.urlEncoded)&endTime=\(endTime.urlEncoded)") else {
            throw TokenProviderError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 15

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TokenProviderError.invalidResponse
        }
        if http.statusCode == 401 { throw TokenProviderError.invalidAPIKey }
        guard http.statusCode == 200 else {
            throw TokenProviderError.serverError(http.statusCode)
        }

        let resp: GLMModelUsageResponse
        do {
            resp = try JSONDecoder().decode(GLMModelUsageResponse.self, from: data)
        } catch {
            throw TokenProviderError.invalidResponse
        }

        if resp.code == 401 { throw TokenProviderError.invalidAPIKey }
        guard resp.code == 200 || resp.code == 0 else {
            throw TokenProviderError.serverError(resp.code ?? -1)
        }

        return resp
    }

    private func fetchQuotaLimit(base: String, apiKey: String) async throws -> GLMQuotaLimitResponse {
        guard let url = URL(string: "\(base)/api/monitor/usage/quota/limit") else {
            throw TokenProviderError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TokenProviderError.invalidResponse
        }

        let resp = try JSONDecoder().decode(GLMQuotaLimitResponse.self, from: data)
        if resp.code == 401 { throw TokenProviderError.invalidAPIKey }
        return resp
    }

    private func buildDistribution(from response: GLMModelUsageResponse, windowStart: Date, windowEnd: Date) -> UsageDistribution {
        guard let xTime = response.data?.xTime, let tokensUsage = response.data?.tokensUsage else {
            return UsageDistribution(providerId: id, windowStart: windowStart, windowEnd: windowEnd, points: [])
        }

        let hourlyFormatter = DateFormatter()
        hourlyFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let dailyFormatter = DateFormatter()
        dailyFormatter.dateFormat = "yyyy-MM-dd"

        let points = zip(xTime, tokensUsage).compactMap { timeStr, count -> UsagePoint? in
            let trimmed = timeStr.trimmingCharacters(in: .whitespaces)
            guard let date = hourlyFormatter.date(from: trimmed) ?? dailyFormatter.date(from: trimmed) else { return nil }
            return UsagePoint(time: date, count: count)
        }

        return UsageDistribution(providerId: id, windowStart: windowStart, windowEnd: windowEnd, points: points, totalTokens: response.data?.totalUsage?.totalTokensUsage)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}

// MARK: - Response Models

struct GLMModelUsageResponse: Decodable {
    let code: Int?
    let msg: String?
    let data: ModelUsageData?

    struct ModelUsageData: Decodable {
        let totalUsage: TotalUsage?
        let modelSummaryList: [ModelSummary]?
        let xTime: [String]?
        let tokensUsage: [Int]?

        enum CodingKeys: String, CodingKey {
            case totalUsage = "totalUsage"
            case modelSummaryList = "modelSummaryList"
            case xTime = "x_time"
            case tokensUsage
        }

        struct TotalUsage: Decodable {
            let totalModelCallCount: Int?
            let totalTokensUsage: Int?
            let modelSummaryList: [ModelSummary]?

            enum CodingKeys: String, CodingKey {
                case totalModelCallCount = "totalModelCallCount"
                case totalTokensUsage = "totalTokensUsage"
                case modelSummaryList = "modelSummaryList"
            }
        }

        struct ModelSummary: Decodable {
            let modelName: String?
            let totalTokens: Int?

            enum CodingKeys: String, CodingKey {
                case modelName = "modelName"
                case totalTokens = "totalTokens"
            }
        }
    }
}

struct GLMQuotaLimitResponse: Decodable {
    let code: Int?
    let data: QuotaData?

    struct QuotaData: Decodable {
        let limits: [QuotaLimit]?
        let level: String?
    }

    struct QuotaLimit: Decodable {
        let type: String?
        let percentage: Int?
        let nextResetTime: TimeInterval?
        let usage: Int?
        let currentValue: Int?
        let remaining: Int?

        enum CodingKeys: String, CodingKey {
            case type, percentage, usage, remaining
            case nextResetTime = "nextResetTime"
            case currentValue = "currentValue"
        }
    }
}

private extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
