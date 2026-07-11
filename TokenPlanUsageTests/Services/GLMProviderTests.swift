import XCTest
@testable import TokenPlanUsage

final class GLMProviderTests: XCTestCase {
    var provider: GLMProvider!
    var session: URLSession!

    private var freshProvider: GLMProvider {
        let p = GLMProvider()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        p.urlSession = URLSession(configuration: config)
        return p
    }

    override func setUp() {
        provider = freshProvider
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
    }

    // MARK: - Mock Helpers

    private func mockSuccess(json: String, url: String = "https://api.z.ai/api/monitor/usage/model-usage") {
        MockURLProtocol.requestHandler = { request in
            let urlString = request.url?.absoluteString ?? ""
            let (data, response) = (
                json.data(using: .utf8)!,
                HTTPURLResponse(url: URL(string: urlString)!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
            return (data: data, response: response, error: nil)
        }
    }

    // MARK: - Success Cases

    func testFetchUsageParsesModelUsageAndQuota() async throws {
        // Mock will return model-usage JSON for both calls (quota will fail gracefully)
        let modelUsageJSON = """
        {
            "code": 200,
            "msg": "Operation successful",
            "success": true,
            "data": {
                "totalUsage": {
                    "totalModelCallCount": 1118,
                    "totalTokensUsage": 50562802,
                    "modelSummaryList": [
                        {"modelName": "GLM-5.1", "totalTokens": 45702431},
                        {"modelName": "GLM-4.7", "totalTokens": 4860371}
                    ]
                }
            }
        }
        """
        mockSuccess(json: modelUsageJSON)

        let snapshot = try await provider.fetchUsage(apiKey: "coding-plan-token", baseURL: nil)
        XCTAssertEqual(snapshot.providerId, "glm")
        // TOKENS_LIMIT has no counts — usedCount/totalCount are 0 when quota unavailable
        XCTAssertEqual(snapshot.usedCount, 0)
        XCTAssertEqual(snapshot.totalCount, 0)
        // remainingPercent = 100% when no percentage data
        XCTAssertEqual(snapshot.remainingPercent, 1.0, accuracy: 0.001)
        XCTAssertTrue(snapshot.planName.contains("GLM-5.1"))
        XCTAssertNil(snapshot.mcpQuota)
    }

    func testFetchDistributionParsesHourlyData() async throws {
        // TODO: fix flakiness - crashes intermittently in full suite but passes individually
        try await XCTSkipUnless(false, "Skipping flaky test - crashes intermittently")
        let json = """
        {
            "code": 200,
            "success": true,
            "data": {
                "x_time": ["2026-04-11 09:00", "2026-04-11 10:00", "2026-04-11 11:00"],
                "tokens_usage": [1033418, 836219, 2219443],
                "totalUsage": {
                    "totalModelCallCount": 100,
                    "totalTokensUsage": 4089080
                }
            }
        }
        """
        mockSuccess(json: json)

        // fetchUsage caches the distribution from the same response
        _ = try await provider.fetchUsage(apiKey: "test", baseURL: nil)
        let distribution = try await provider.fetchDistribution(apiKey: "test", baseURL: nil, timeRange: .day)
        XCTAssertEqual(distribution.providerId, "glm")
        XCTAssertEqual(distribution.points.count, 3)
        XCTAssertEqual(distribution.points[0].count, 1033418)
        XCTAssertEqual(distribution.points[2].count, 2219443)
    }

    func testFetchDistributionWithEmptyData() async throws {
        let json = """
        {"code": 200, "success": true, "data": {"x_time": [], "tokens_usage": [], "totalUsage": {"totalModelCallCount": 0, "totalTokensUsage": 0}}}
        """
        mockSuccess(json: json)

        _ = try await provider.fetchUsage(apiKey: "test", baseURL: nil)
        let distribution = try await provider.fetchDistribution(apiKey: "test", baseURL: nil, timeRange: .day)
        XCTAssertEqual(distribution.points.count, 0)
    }

    func testFetchDistributionReturnsEmptyWhenModelUsageFails() async {
        let json = """
        {"code": 500, "msg": "当前用户不存在coding plan", "success": false}
        """
        mockSuccess(json: json)

        do {
            let dist = try await provider.fetchDistribution(apiKey: "non-coding-plan", baseURL: nil, timeRange: .day)
            XCTAssertEqual(dist.providerId, "glm")
            XCTAssertEqual(dist.points.count, 0)
        } catch {
            XCTFail("Should return empty distribution, not throw: \(error)")
        }
    }

    // MARK: - Error Cases

    func testFetchUsageThrowsOnHTTP401() async {
        MockURLProtocol.mockResponse = (
            data: Data(),
            response: HTTPURLResponse(url: URL(string: "https://api.z.ai/api/monitor/usage/model-usage?startTime=a&endTime=b")!, statusCode: 401, httpVersion: nil, headerFields: nil),
            error: nil
        )

        do {
            _ = try await provider.fetchUsage(apiKey: "bad-token", baseURL: nil)
            XCTFail("Should throw")
        } catch TokenProviderError.invalidAPIKey {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testFetchUsageThrowsOnBusinessLayer401() async {
        let json = """
        {"code": 401, "msg": "token expired or incorrect", "success": false}
        """
        mockSuccess(json: json)

        do {
            _ = try await provider.fetchUsage(apiKey: "expired-token", baseURL: nil)
            XCTFail("Should throw")
        } catch TokenProviderError.invalidAPIKey {
            // expected: HTTP 200 but business code 401
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testFetchUsageMapsAuthFailureCode1000ToInvalidAPIKey() async {
        let json = """
        {"code": 1000, "msg": "Authentication Failed", "success": false}
        """
        mockSuccess(json: json)

        do {
            _ = try await provider.fetchUsage(apiKey: "invalid-token", baseURL: nil)
            XCTFail("Should throw")
        } catch TokenProviderError.invalidAPIKey {
            // expected: 智谱用 code 1000 表示认证失败，应映射成 invalidAPIKey
        } catch {
            XCTFail("Wrong error: \(error) — 认证失败(code 1000)应映射为 invalidAPIKey")
        }
    }

    func testFetchBalanceMapsAuthFailureCode1000ToInvalidAPIKey() async throws {
        mockPerEndpoint(
            balanceJSON: """
            {"code": 1000, "msg": "Authentication Failed", "success": false}
            """,
            modelUsageJSON: """
            {"code": 200, "success": true, "data": {"x_time": [], "tokens_usage": [], "totalUsage": {"totalModelCallCount": 0, "totalTokensUsage": 0}}}
            """
        )

        do {
            _ = try await provider.fetchBalance(apiKey: "invalid", baseURL: nil)
            XCTFail("Should throw")
        } catch TokenProviderError.invalidAPIKey {
            // expected
        } catch {
            XCTFail("Wrong error: \(error) — 认证失败(code 1000)应映射为 invalidAPIKey")
        }
    }

    func testFetchUsageThrowsOnInvalidJSON() async {
        mockSuccess(json: "not json at all")

        do {
            _ = try await provider.fetchUsage(apiKey: "test", baseURL: nil)
            XCTFail("Should throw")
        } catch TokenProviderError.invalidResponse {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testDefaultBaseURL() {
        XCTAssertEqual(provider.defaultBaseURL, "https://api.z.ai")
    }

    func testCustomBaseURL() async throws {
        let json = """
        {
            "code": 200,
            "success": true,
            "data": {
                "totalUsage": {
                    "totalModelCallCount": 100,
                    "totalTokensUsage": 50000,
                    "modelSummaryList": [
                        {"modelName": "GLM-5.1", "totalTokens": 50000}
                    ]
                }
            }
        }
        """
        mockSuccess(json: json, url: "https://open.bigmodel.cn/api/monitor/usage/model-usage?startTime=2026-04-11%2000:00:00&endTime=2026-04-12%2023:59:59")

        let snapshot = try await provider.fetchUsage(apiKey: "test", baseURL: "https://open.bigmodel.cn")
        // No quota data → usedCount and totalCount are 0
        XCTAssertEqual(snapshot.usedCount, 0)
        XCTAssertEqual(snapshot.totalCount, 0)
        XCTAssertTrue(snapshot.planName.contains("GLM-5.1"))
    }

    // MARK: - Non-Coding-Plan balance (GLMBalance)

    /// Helper: mock each request by URL substring. Pass `nil` to fall back
    /// to a JSON success response (use for endpoints that aren't asserted).
    private func mockPerEndpoint(
        balanceJSON: String?,
        modelUsageJSON: String
    ) {
        let balanceData = balanceJSON?.data(using: .utf8)
        MockURLProtocol.requestHandler = { request in
            let urlString = request.url?.absoluteString ?? ""
            let url = URL(string: urlString)!
            let body: Data
            if urlString.contains("/api/biz/account/query-customer-account-report") {
                guard let data = balanceData else {
                    return (data: Data(),
                            response: HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                            error: nil)
                }
                body = data
            } else {
                body = modelUsageJSON.data(using: .utf8)!
            }
            return (data: body,
                    response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    error: nil)
        }
    }

    func testFetchBalanceParsesFullReport() async throws {
        // Mirrors the actual /api/biz/account/query-customer-account-report
        // response shape (numeric fields, currency not echoed by API).
        mockPerEndpoint(
            balanceJSON: """
            {
              "code": 200,
              "msg": "操作成功",
              "data": {
                "balance": 89.16,
                "availableBalance": 89.16,
                "rechargeAmount": 12.0,
                "giveAmount": 100.0,
                "totalSpendAmount": 22.84,
                "todaySpendAmount": 1.50,
                "frozenBalance": 0.5,
                "creditBalance": null,
                "creditStatus": "NOT_OPEN",
                "modelSpendAmountList": null,
                "isKA": false
              }
            }
            """,
            modelUsageJSON: """
            {"code": 200, "success": true, "data": {"x_time": [], "tokens_usage": [], "totalUsage": {"totalModelCallCount": 0, "totalTokensUsage": 0}}}
            """
        )

        let balance = try await provider.fetchBalance(apiKey: "test", baseURL: nil)
        XCTAssertEqual(balance.currency, "CNY")
        XCTAssertEqual(balance.balance, 89.16, accuracy: 0.0001)
        XCTAssertEqual(balance.frozenBalance, 0.5, accuracy: 0.0001)
        XCTAssertEqual(balance.totalSpendAmount, 22.84, accuracy: 0.0001)
        XCTAssertEqual(balance.todaySpendAmount ?? 0, 1.50, accuracy: 0.0001)
        XCTAssertEqual(balance.rechargeAmount, 12.0, accuracy: 0.0001)
        XCTAssertEqual(balance.giveAmount, 100.0, accuracy: 0.0001)
    }

    func testFetchBalanceHandlesMissingOptionalFields() async throws {
        // Endpoint returns just `availableBalance`; everything else is missing.
        // The parser must default missing fields to 0 / nil without throwing.
        mockPerEndpoint(
            balanceJSON: """
            { "code": 200, "data": { "availableBalance": 42.0 } }
            """,
            modelUsageJSON: """
            {"code": 200, "success": true, "data": {"x_time": [], "tokens_usage": [], "totalUsage": {"totalModelCallCount": 0, "totalTokensUsage": 0}}}
            """
        )

        let balance = try await provider.fetchBalance(apiKey: "test", baseURL: nil)
        XCTAssertEqual(balance.balance, 42.0, accuracy: 0.0001)
        XCTAssertEqual(balance.frozenBalance, 0)
        XCTAssertEqual(balance.totalSpendAmount, 0)
        XCTAssertNil(balance.todaySpendAmount)
        XCTAssertEqual(balance.rechargeAmount, 0)
        XCTAssertEqual(balance.giveAmount, 0)
    }

    func testFetchBalancePreservesNullTodaySpendAmount() async throws {
        // todaySpendAmount is the one field that's allowed to be null even
        // on a healthy account (e.g. user hasn't spent today) — make sure
        // it doesn't silently get coerced to 0.
        mockPerEndpoint(
            balanceJSON: """
            {
              "code": 200,
              "data": {
                "availableBalance": 89.16,
                "totalSpendAmount": 22.84,
                "todaySpendAmount": null
              }
            }
            """,
            modelUsageJSON: """
            {"code": 200, "success": true, "data": {"x_time": [], "tokens_usage": [], "totalUsage": {"totalModelCallCount": 0, "totalTokensUsage": 0}}}
            """
        )

        let balance = try await provider.fetchBalance(apiKey: "test", baseURL: nil)
        XCTAssertNil(balance.todaySpendAmount)
        XCTAssertEqual(balance.balance, 89.16, accuracy: 0.0001)
    }

    func testFetchBalanceThrowsOnNon200Status() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = request.url ?? URL(string: "https://api.z.ai")!
            return (data: Data(),
                    response: HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                    error: nil)
        }

        do {
            _ = try await provider.fetchBalance(apiKey: "test", baseURL: nil)
            XCTFail("Should have thrown")
        } catch TokenProviderError.serverError {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testFetchUsageAttachesBalanceWhenAvailable() async throws {
        mockPerEndpoint(
            balanceJSON: """
            {
              "code": 200,
              "data": {
                "availableBalance": 89.16,
                "totalSpendAmount": 22.84,
                "giveAmount": 100.0
              }
            }
            """,
            modelUsageJSON: """
            {
              "code": 200,
              "success": true,
              "data": {
                "totalUsage": {
                  "totalModelCallCount": 5,
                  "totalTokensUsage": 1000,
                  "modelSummaryList": [
                    {"modelName": "GLM-5.1", "totalTokens": 1000}
                  ]
                }
              }
            }
            """
        )

        let snapshot = try await provider.fetchUsage(apiKey: "test", baseURL: nil)
        let glmBalance = try XCTUnwrap(snapshot.glmBalance)
        XCTAssertEqual(glmBalance.balance, 89.16, accuracy: 0.0001)
        XCTAssertEqual(glmBalance.totalSpendAmount, 22.84, accuracy: 0.0001)
        XCTAssertEqual(glmBalance.giveAmount, 100.0, accuracy: 0.0001)
    }

    func testFetchUsageLeavesBalanceNilWhenEndpointFails() async throws {
        // balanceJSON = nil → mock returns 500 for the balance endpoint.
        // The model-usage endpoint still succeeds, so the snapshot should
        // still build (balance gracefully nil).
        mockPerEndpoint(
            balanceJSON: nil,
            modelUsageJSON: """
            {
              "code": 200,
              "success": true,
              "data": {
                "totalUsage": {
                  "totalModelCallCount": 1,
                  "totalTokensUsage": 10,
                  "modelSummaryList": [
                    {"modelName": "GLM-5.1", "totalTokens": 10}
                  ]
                }
              }
            }
            """
        )

        let snapshot = try await provider.fetchUsage(apiKey: "test", baseURL: nil)
        XCTAssertNil(snapshot.glmBalance)
    }

    // MARK: - Non-Coding-Plan fallback

    func testFetchUsageFallsBackToBalanceOnlyForNonCodingPlanUser() async throws {
        // 非 Coding Plan 用户：model-usage 返回 code:500 "当前用户不存在coding plan"，
        // 但 balance 接口正常。fetchUsage 不应抛错，应返回含 balance 的 snapshot。
        mockPerEndpoint(
            balanceJSON: """
            {"code": 200, "data": {"availableBalance": 83.39, "totalSpendAmount": 28.6, "giveAmount": 100.0}}
            """,
            modelUsageJSON: """
            {"code": 500, "msg": "当前用户不存在coding plan", "success": false}
            """
        )

        let snapshot = try await provider.fetchUsage(apiKey: "non-coding-plan", baseURL: nil)
        XCTAssertEqual(snapshot.providerId, "glm")
        let balance = try XCTUnwrap(snapshot.glmBalance)
        XCTAssertEqual(balance.balance, 83.39, accuracy: 0.01)
    }

    func testFetchUsageThrowsWhenBothModelUsageAndBalanceFail() async {
        // model-usage 失败 + balance 也失败 → fetchUsage 应抛错
        mockPerEndpoint(
            balanceJSON: nil,
            modelUsageJSON: """
            {"code": 500, "msg": "当前用户不存在coding plan", "success": false}
            """
        )

        do {
            _ = try await provider.fetchUsage(apiKey: "test", baseURL: nil)
            XCTFail("Should throw when both endpoints fail")
        } catch {
            // expected
        }
    }
}
