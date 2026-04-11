import XCTest
@testable import TokenPlanUsage

final class MiniMaxProviderTests: XCTestCase {

    var provider: MiniMaxProvider!
    var session: URLSession!

    override func setUp() {
        super.setUp()
        provider = MiniMaxProvider()
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
                "total": 600,
                "used": 25,
                "plan_name": "MiniMax-M2.7"
            }
        }
        """.data(using: .utf8)!

        MockURLProtocol.mockHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let snapshot = try await provider.fetchUsage(apiKey: "test-key", baseURL: nil)
        XCTAssertEqual(snapshot.usedCount, 25)
        XCTAssertEqual(snapshot.totalCount, 600)
        XCTAssertEqual(snapshot.providerId, "minimax")
        XCTAssertEqual(snapshot.planName, "MiniMax-M2.7")
        XCTAssertEqual(snapshot.remainingPercent, 575.0 / 600.0, accuracy: 0.001)
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
        {"data": {"total": 100, "used": 0, "plan_name": null}}
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
        XCTAssertEqual(dist.providerId, "minimax")
        XCTAssertEqual(dist.points.count, 0)
    }

    func testProviderProperties() {
        XCTAssertEqual(provider.id, "minimax")
        XCTAssertEqual(provider.displayName, "MiniMax")
        XCTAssertEqual(provider.defaultBaseURL, "https://api.minimax.chat")
    }
}

// Shared mock URLProtocol for provider tests
final class MockURLProtocol: URLProtocol {
    static var mockHandler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.mockHandler else { return }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
