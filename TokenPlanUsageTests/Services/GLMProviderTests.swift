import XCTest
@testable import TokenPlanUsage

final class GLMProviderTests: XCTestCase {
    var provider: GLMProvider!
    var session: URLSession!

    override func setUp() {
        provider = GLMProvider()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        provider.urlSession = session
    }

    override func tearDown() {
        MockURLProtocol.mockResponse = (data: nil, response: nil, error: nil)
    }

    // MARK: - Mock Helpers

    private func mockSuccess(json: String, url: String = "https://api.z.ai/api/monitor/usage/model-usage") {
        // Build query params for model-usage URL
        let fullURL = url.contains("?") ? url : url + "?startTime=2026-04-11%2000:00:00&endTime=2026-04-12%2023:59:59"
        MockURLProtocol.mockResponse = (
            data: json.data(using: .utf8),
            response: HTTPURLResponse(url: URL(string: fullURL)!, statusCode: 200, httpVersion: nil, headerFields: nil),
            error: nil
        )
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
        let distribution = try await provider.fetchDistribution(apiKey: "test", baseURL: nil)
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
        let distribution = try await provider.fetchDistribution(apiKey: "test", baseURL: nil)
        XCTAssertEqual(distribution.points.count, 0)
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
}
