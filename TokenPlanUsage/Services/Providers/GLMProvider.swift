import Foundation

class GLMProvider: TokenProvider {
    let id = "glm"
    let displayName = "GLM（智谱）"
    let defaultBaseURL = "https://api.z.ai"
    var urlSession: URLSession = .shared

    func fetchUsage(apiKey: String, baseURL: String?) async throws -> UsageSnapshot {
        let base = baseURL ?? defaultBaseURL

        // Fetch model usage and quota limit in parallel
        async let modelUsageTask = fetchModelUsage(base: base, apiKey: apiKey)
        async let quotaTask = fetchQuotaLimit(base: base, apiKey: apiKey)

        let modelUsage = try await modelUsageTask
        let quota: GLMQuotaLimitResponse? = (try? await quotaTask)

        // Extract data from model usage
        let totalUsage = modelUsage.data?.totalUsage
        let usedTokens = totalUsage?.totalTokensUsage ?? 0
        let modelCallCount = totalUsage?.totalModelCallCount ?? 0

        // Extract quota info
        let tokensLimit = quota?.data?.limits?.first(where: { $0.type == "TOKENS_LIMIT" })
        let tokensPercentage = tokensLimit?.percentage ?? 0 // percentage of quota used
        let nextResetTime = tokensLimit?.nextResetTime.map { Date(timeIntervalSince1970: $0 / 1000) }

        // Build plan name from models
        let modelNames = totalUsage?.modelSummaryList?.map { $0.modelName ?? "" }.joined(separator: " + ") ?? "GLM"

        return UsageSnapshot(
            providerId: id,
            planName: "GLM Coding Plan (\(modelNames))",
            usedCount: usedTokens,
            totalCount: 0, // No total from API — use percentage instead
            remainingPercent: Double(100 - tokensPercentage) / 100.0,
            refreshTime: nextResetTime,
            fetchedAt: Date(),
            status: .normal
        )
    }

    func fetchDistribution(apiKey: String, baseURL: String?) async throws -> UsageDistribution {
        let base = baseURL ?? defaultBaseURL
        let now = Date()
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -1, to: now) ?? now

        let startTime = formatDate(startDate)
        let endTime = formatDate(now)

        guard let url = URL(string: "\(base)/api/monitor/usage/model-usage?startTime=\(startTime.urlEncoded)&endTime=\(endTime.urlEncoded)") else {
            throw TokenProviderError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TokenProviderError.invalidResponse
        }

        return try parseDistribution(data, windowStart: startDate, windowEnd: now)
    }

    // MARK: - Private

    private func fetchModelUsage(base: String, apiKey: String) async throws -> GLMModelUsageResponse {
        let now = Date()
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -1, to: now) ?? now

        let startTime = formatDate(startDate)
        let endTime = formatDate(now)

        guard let url = URL(string: "\(base)/api/monitor/usage/model-usage?startTime=\(startTime.urlEncoded)&endTime=\(endTime.urlEncoded)") else {
            throw TokenProviderError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
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
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
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

    private func parseDistribution(_ data: Data, windowStart: Date, windowEnd: Date) throws -> UsageDistribution {
        struct Response: Decodable {
            let data: DataClass?
            let code: Int?

            struct DataClass: Decodable {
                let xTime: [String]?
                let tokensUsage: [Int]?

                enum CodingKeys: String, CodingKey {
                    case xTime = "x_time"
                    case tokensUsage = "tokens_usage"
                }
            }
        }

        let resp = try JSONDecoder().decode(Response.self, from: data)

        guard let xTime = resp.data?.xTime, let tokensUsage = resp.data?.tokensUsage else {
            return UsageDistribution(providerId: id, windowStart: windowStart, windowEnd: windowEnd, points: [])
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        let points = zip(xTime, tokensUsage).compactMap { timeStr, count -> UsagePoint? in
            guard let date = formatter.date(from: timeStr) else { return nil }
            return UsagePoint(time: date, count: count)
        }

        return UsageDistribution(
            providerId: id,
            windowStart: windowStart,
            windowEnd: windowEnd,
            points: points
        )
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
            case tokensUsage = "tokens_usage"
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
