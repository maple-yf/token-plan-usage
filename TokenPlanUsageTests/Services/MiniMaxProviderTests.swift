import XCTest
@testable import TokenPlanUsage

class MockURLProtocol: URLProtocol {
    static var mockResponse: (data: Data?, response: HTTPURLResponse?, error: Error?)
    static var requestHandler: ((URLRequest) -> (data: Data, response: HTTPURLResponse, error: Error?))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let handler = Self.requestHandler {
            let result = handler(request)
            if let error = result.error {
                client?.urlProtocol(self, didFailWithError: error)
            } else {
                client?.urlProtocol(self, didReceive: result.response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: result.data)
            }
        } else {
            if let error = Self.mockResponse.error {
                client?.urlProtocol(self, didFailWithError: error)
            } else {
                if let response = Self.mockResponse.response {
                    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                }
                if let data = Self.mockResponse.data {
                    client?.urlProtocol(self, didLoad: data)
                }
            }
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class MiniMaxProviderTests: XCTestCase {
    var provider: MiniMaxProvider!
    var session: URLSession!

    override func setUp() {
        provider = MiniMaxProvider()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        provider.urlSession = session
    }

    override func tearDown() {
        MockURLProtocol.mockResponse = (data: nil, response: nil, error: nil)
    }

    // MARK: - Success Cases

    func testFetchUsageParsesCorrectly() async throws {
        let json = """
        {
            "model_remains": [
                {
                    "remains_time": 14449904,
                    "current_interval_remaining_percent": 95.83,
                    "model_name": "MiniMax-M*",
                    "current_weekly_status": 3,
                    "current_weekly_remaining_percent": 100.0
                }
            ],
            "base_resp": {"status_code": 0, "status_msg": "success"}
        }
        """.data(using: .utf8)!

        MockURLProtocol.mockResponse = (
            data: json,
            response: HTTPURLResponse(url: URL(string: "https://www.minimaxi.com/v1/api/openplatform/coding_plan/remains")!, statusCode: 200, httpVersion: nil, headerFields: nil),
            error: nil
        )

        let snapshot = try await provider.fetchUsage(apiKey: "test-key", baseURL: nil)
        XCTAssertEqual(snapshot.providerId, "minimax")
        XCTAssertEqual(snapshot.planName, "MiniMax-M*")
        // Real API returns percentage-based quotas. usedCount/totalCount are 0
        // in percentage mode; remainingPercent is a 0-1 ratio.
        XCTAssertEqual(snapshot.usedCount, 0)
        XCTAssertEqual(snapshot.totalCount, 0)
        XCTAssertEqual(snapshot.remainingPercent, 0.9583, accuracy: 0.001)
        XCTAssertNotNil(snapshot.refreshTime)

        // Per-model quotas are populated from the response.
        let quota = try XCTUnwrap(snapshot.modelQuotas?.first)
        XCTAssertEqual(quota.modelName, "MiniMax-M*")
        XCTAssertEqual(quota.intervalRemainingPercent, 95.83, accuracy: 0.001)
        XCTAssertEqual(quota.weeklyStatus, 3)
        XCTAssertEqual(quota.weeklyRemainingPercent, 100.0)
        XCTAssertTrue(quota.isWeeklyUnlimited)
    }

    func testFetchUsageWithMultipleModels() async throws {
        let json = """
        {
            "model_remains": [
                {
                    "remains_time": 14449904,
                    "current_interval_remaining_percent": 1.6,
                    "model_name": "speech-hd",
                    "current_weekly_status": 0,
                    "current_weekly_remaining_percent": 1.6
                },
                {
                    "remains_time": 14449904,
                    "current_interval_remaining_percent": 0.13,
                    "model_name": "MiniMax-M*",
                    "current_weekly_status": 3,
                    "current_weekly_remaining_percent": 100.0
                }
            ],
            "base_resp": {"status_code": 0, "status_msg": "success"}
        }
        """.data(using: .utf8)!

        MockURLProtocol.mockResponse = (
            data: json,
            response: HTTPURLResponse(url: URL(string: "https://www.minimaxi.com/v1/api/openplatform/coding_plan/remains")!, statusCode: 200, httpVersion: nil, headerFields: nil),
            error: nil
        )

        let snapshot = try await provider.fetchUsage(apiKey: "test-key", baseURL: nil)
        // Should pick MiniMax-M* over speech-hd as the primary plan
        XCTAssertEqual(snapshot.planName, "MiniMax-M*")
        XCTAssertEqual(snapshot.remainingPercent, 0.0013, accuracy: 0.0001)

        // All models should appear in modelQuotas
        XCTAssertEqual(snapshot.modelQuotas?.count, 2)
        let speechQuota = try XCTUnwrap(snapshot.modelQuotas?.first(where: { $0.modelName == "speech-hd" }))
        XCTAssertEqual(speechQuota.intervalRemainingPercent, 1.6, accuracy: 0.001)
        XCTAssertEqual(speechQuota.isWeeklyUnlimited, false)
    }

    func testFetchUsageFallsBackToFirstModel() async throws {
        let json = """
        {
            "model_remains": [
                {
                    "remains_time": 14449904,
                    "current_interval_remaining_percent": 80.0,
                    "model_name": "speech-hd",
                    "current_weekly_status": 3,
                    "current_weekly_remaining_percent": 100.0
                }
            ],
            "base_resp": {"status_code": 0, "status_msg": "success"}
        }
        """.data(using: .utf8)!

        MockURLProtocol.mockResponse = (
            data: json,
            response: HTTPURLResponse(url: URL(string: "https://www.minimaxi.com/v1/api/openplatform/coding_plan/remains")!, statusCode: 200, httpVersion: nil, headerFields: nil),
            error: nil
        )

        let snapshot = try await provider.fetchUsage(apiKey: "test-key", baseURL: nil)
        XCTAssertEqual(snapshot.planName, "speech-hd")
        XCTAssertEqual(snapshot.remainingPercent, 0.8, accuracy: 0.001)
    }

    // MARK: - Error Cases

    func testFetchUsageThrowsOn401() async {
        MockURLProtocol.mockResponse = (
            data: Data(),
            response: HTTPURLResponse(url: URL(string: "https://www.minimaxi.com/v1/api/openplatform/coding_plan/remains")!, statusCode: 401, httpVersion: nil, headerFields: nil),
            error: nil
        )

        do {
            _ = try await provider.fetchUsage(apiKey: "bad-key", baseURL: nil)
            XCTFail("Should throw")
        } catch TokenProviderError.invalidAPIKey {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testFetchUsageThrowsOnServerError() async {
        MockURLProtocol.mockResponse = (
            data: Data(),
            response: HTTPURLResponse(url: URL(string: "https://www.minimaxi.com/v1/api/openplatform/coding_plan/remains")!, statusCode: 500, httpVersion: nil, headerFields: nil),
            error: nil
        )

        do {
            _ = try await provider.fetchUsage(apiKey: "test-key", baseURL: nil)
            XCTFail("Should throw")
        } catch TokenProviderError.serverError(let code) {
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testFetchUsageThrowsOnInvalidJSON() async {
        MockURLProtocol.mockResponse = (
            data: "not json".data(using: .utf8),
            response: HTTPURLResponse(url: URL(string: "https://www.minimaxi.com/v1/api/openplatform/coding_plan/remains")!, statusCode: 200, httpVersion: nil, headerFields: nil),
            error: nil
        )

        do {
            _ = try await provider.fetchUsage(apiKey: "test-key", baseURL: nil)
            XCTFail("Should throw")
        } catch TokenProviderError.invalidResponse {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testFetchUsageThrowsOnAPIError() async {
        let json = """
        {"base_resp": {"status_code": 1001, "status_msg": "invalid token"}}
        """.data(using: .utf8)!

        MockURLProtocol.mockResponse = (
            data: json,
            response: HTTPURLResponse(url: URL(string: "https://www.minimaxi.com/v1/api/openplatform/coding_plan/remains")!, statusCode: 200, httpVersion: nil, headerFields: nil),
            error: nil
        )

        do {
            _ = try await provider.fetchUsage(apiKey: "test-key", baseURL: nil)
            XCTFail("Should throw")
        } catch TokenProviderError.serverError(let code) {
            XCTAssertEqual(code, 1001)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testDefaultBaseURL() {
        XCTAssertEqual(provider.defaultBaseURL, "https://www.minimaxi.com")
    }

    func testCustomBaseURL() async throws {
        let json = """
        {
            "model_remains": [
                {
                    "current_interval_remaining_percent": 50.0,
                    "model_name": "MiniMax-M*",
                    "current_weekly_status": 3,
                    "current_weekly_remaining_percent": 100.0
                }
            ],
            "base_resp": {"status_code": 0, "status_msg": "success"}
        }
        """.data(using: .utf8)!

        MockURLProtocol.mockResponse = (
            data: json,
            response: HTTPURLResponse(url: URL(string: "https://custom.minimax.com/v1/api/openplatform/coding_plan/remains")!, statusCode: 200, httpVersion: nil, headerFields: nil),
            error: nil
        )

        let snapshot = try await provider.fetchUsage(apiKey: "test", baseURL: "https://custom.minimax.com")
        // Real API is percentage-based; 50% remaining means remainingPercent = 0.5
        XCTAssertEqual(snapshot.remainingPercent, 0.5, accuracy: 0.001)
    }
}
