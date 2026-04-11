import XCTest
@testable import TokenPlanUsage

final class GLMProviderTests: XCTestCase {

    var provider: GLMProvider!
    var session: URLSession!

    override func setUp() {
        super.setUp()
        provider = GLMProvider()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        provider.urlSession = session
    }

    override func tearDown() {
        MockURLProtocol.mockHandler = nil
        super.tearDown()
    }

    func testFetchUsageParsesCorrectly() async throws {
        let json = """
        {
            "data": {
                "total_tokens": 1000000,
                "used_tokens": 25000,
                "remaining_tokens": 975000,
                "plan_name": "GLM-4-Plus"
            }
        }
        """.data(using: .utf8)!

        MockURLProtocol.mockHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let snapshot = try await provider.fetchUsage(apiKey: "test-key", baseURL: nil)
        XCTAssertEqual(snapshot.usedCount, 25000)
        XCTAssertEqual(snapshot.totalCount, 1000000)
        XCTAssertEqual(snapshot.providerId, "glm")
        XCTAssertEqual(snapshot.planName, "GLM-4-Plus")
        XCTAssertEqual(snapshot.remainingPercent, 975000.0 / 1000000.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.status, .normal)
    }

    func testFetchUsageThrowsOn401() async {
        MockURLProtocol.mockHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        do {
            _ = try await provider.fetchUsage(apiKey: "bad-key", baseURL: nil)
            XCTFail("Should throw")
        } catch TokenProviderError.invalidAPIKey {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testFetchUsageThrowsOn500() async {
        MockURLProtocol.mockHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        do {
            _ = try await provider.fetchUsage(apiKey: "key", baseURL: nil)
            XCTFail("Should throw")
        } catch TokenProviderError.serverError(500) {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testFetchUsageThrowsOnInvalidJSON() async {
        MockURLProtocol.mockHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "not json".data(using: .utf8)!)
        }

        do {
            _ = try await provider.fetchUsage(apiKey: "key", baseURL: nil)
            XCTFail("Should throw")
        } catch TokenProviderError.invalidResponse {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testFetchUsageUsesCustomBaseURL() async throws {
        let json = """
        {"data": {"total_tokens": 100000, "used_tokens": 0, "remaining_tokens": 100000, "plan_name": null}}
        """.data(using: .utf8)!

        MockURLProtocol.mockHandler = { request in
            XCTAssertEqual(request.url?.host, "custom.api.com")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        _ = try await provider.fetchUsage(apiKey: "key", baseURL: "https://custom.api.com")
    }

    func testFetchDistributionReturnsEmpty() async throws {
        let dist = try await provider.fetchDistribution(apiKey: "key", baseURL: nil)
        XCTAssertEqual(dist.providerId, "glm")
        XCTAssertEqual(dist.points.count, 0)
    }

    func testProviderProperties() {
        XCTAssertEqual(provider.id, "glm")
        XCTAssertEqual(provider.displayName, "GLM（智谱）")
        XCTAssertEqual(provider.defaultBaseURL, "https://open.bigmodel.cn/api/paas/v4")
    }
}
