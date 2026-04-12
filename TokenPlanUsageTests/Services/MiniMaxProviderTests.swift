import XCTest
@testable import TokenPlanUsage

class MockURLProtocol: URLProtocol {
    static var mockResponse: (data: Data?, response: HTTPURLResponse?, error: Error?)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
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
                    "start_time": 1775959200000,
                    "end_time": 1775977200000,
                    "remains_time": 14449904,
                    "current_interval_total_count": 600,
                    "current_interval_usage_count": 25,
                    "model_name": "MiniMax-M*",
                    "current_weekly_total_count": 0,
                    "current_weekly_usage_count": 0
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
        XCTAssertEqual(snapshot.usedCount, 25)
        XCTAssertEqual(snapshot.totalCount, 600)
        XCTAssertEqual(snapshot.providerId, "minimax")
        XCTAssertEqual(snapshot.planName, "MiniMax-M*")
        XCTAssertEqual(snapshot.remainingPercent, Double(600 - 25) / Double(600), accuracy: 0.001)
        XCTAssertNotNil(snapshot.refreshTime)
    }

    func testFetchUsageWithMultipleModels() async throws {
        let json = """
        {
            "model_remains": [
                {
                    "start_time": 1775959200000,
                    "end_time": 1775977200000,
                    "remains_time": 14449904,
                    "current_interval_total_count": 100,
                    "current_interval_usage_count": 100,
                    "model_name": "speech-hd",
                    "current_weekly_total_count": 28000,
                    "current_weekly_usage_count": 27556
                },
                {
                    "start_time": 1775959200000,
                    "end_time": 1775977200000,
                    "remains_time": 14449904,
                    "current_interval_total_count": 1500,
                    "current_interval_usage_count": 1498,
                    "model_name": "MiniMax-M*",
                    "current_weekly_total_count": 0,
                    "current_weekly_usage_count": 0
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
        // Should pick MiniMax-M* over speech-hd
        XCTAssertEqual(snapshot.planName, "MiniMax-M*")
        XCTAssertEqual(snapshot.usedCount, 1498)
        XCTAssertEqual(snapshot.totalCount, 1500)
    }

    func testFetchUsageFallsBackToFirstModel() async throws {
        let json = """
        {
            "model_remains": [
                {
                    "start_time": 1775959200000,
                    "end_time": 1775977200000,
                    "remains_time": 14449904,
                    "current_interval_total_count": 50,
                    "current_interval_usage_count": 10,
                    "model_name": "speech-hd"
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
        XCTAssertEqual(snapshot.usedCount, 10)
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
                    "current_interval_total_count": 100,
                    "current_interval_usage_count": 0,
                    "model_name": "MiniMax-M*"
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
        XCTAssertEqual(snapshot.totalCount, 100)
    }
}
