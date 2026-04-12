import XCTest
@testable import TokenPlanUsage

final class MockTokenProvider: TokenProvider {
    let id = "mock"
    let displayName = "Mock Provider"
    let defaultBaseURL = "https://mock.api.com"
    var mockSnapshot: UsageSnapshot?
    var mockDistribution: UsageDistribution?
    var shouldThrow = false

    func fetchUsage(apiKey: String, baseURL: String?) async throws -> UsageSnapshot {
        if shouldThrow { throw TokenProviderError.invalidAPIKey }
        return mockSnapshot!
    }

    func fetchDistribution(apiKey: String, baseURL: String?) async throws -> UsageDistribution {
        if shouldThrow { throw TokenProviderError.networkUnavailable }
        return mockDistribution!
    }
}

final class MockTokenProviderTests: XCTestCase {

    func testFetchUsageSuccess() async throws {
        let provider = MockTokenProvider()
        provider.mockSnapshot = UsageSnapshot(
            providerId: "mock", planName: "Test", usedCount: 10, totalCount: 100,
            remainingPercent: 0.9, refreshTime: nil,
            fetchedAt: Date(timeIntervalSince1970: 1000), status: .normal, mcpQuota: nil, modelQuotas: nil
        )
        let result = try await provider.fetchUsage(apiKey: "test", baseURL: nil)
        XCTAssertEqual(result.usedCount, 10)
        XCTAssertEqual(result.totalCount, 100)
        XCTAssertEqual(result.providerId, "mock")
    }

    func testFetchUsageThrowsInvalidAPIKey() async {
        let provider = MockTokenProvider()
        provider.shouldThrow = true
        do {
            _ = try await provider.fetchUsage(apiKey: "bad", baseURL: nil)
            XCTFail("Should have thrown")
        } catch TokenProviderError.invalidAPIKey {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testFetchDistributionSuccess() async throws {
        let provider = MockTokenProvider()
        provider.mockDistribution = UsageDistribution(
            providerId: "mock",
            windowStart: Date(timeIntervalSince1970: 0),
            windowEnd: Date(timeIntervalSince1970: 3600),
            points: [UsagePoint(time: Date(timeIntervalSince1970: 0), count: 5)]
        )
        let result = try await provider.fetchDistribution(apiKey: "test", baseURL: nil)
        XCTAssertEqual(result.points.count, 1)
        XCTAssertEqual(result.points[0].count, 5)
    }

    func testFetchDistributionThrowsNetworkUnavailable() async {
        let provider = MockTokenProvider()
        provider.shouldThrow = true
        do {
            _ = try await provider.fetchDistribution(apiKey: "test", baseURL: nil)
            XCTFail("Should have thrown")
        } catch TokenProviderError.networkUnavailable {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testTokenProviderErrorDescriptions() {
        XCTAssertEqual(TokenProviderError.invalidAPIKey.errorDescription, "API Key 无效，请检查设置")
        XCTAssertEqual(TokenProviderError.networkUnavailable.errorDescription, "网络不可用")
        XCTAssertEqual(TokenProviderError.serverError(500).errorDescription, "服务端错误 (500)")
        XCTAssertEqual(TokenProviderError.invalidResponse.errorDescription, "响应格式异常")
        XCTAssertEqual(TokenProviderError.timeout.errorDescription, "请求超时")
    }
}
