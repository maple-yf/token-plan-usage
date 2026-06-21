import XCTest
@testable import TokenPlanUsage

/// Tests DeepSeekProvider parsing against the real /usage/cost and /usage/amount
/// response shapes. Sample data mirrors the actual API output (verified against
/// the live endpoint with credentials from .testData).
final class DeepSeekProviderTests: XCTestCase {
    var provider: DeepSeekProvider!
    var session: URLSession!

    override func setUp() {
        super.setUp()
        provider = DeepSeekProvider()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        provider.urlSession = session

        // Inject a fake platform token so fetchPlatformUsage can proceed past
        // its Keychain check. The actual HTTP request is intercepted by MockURLProtocol.
        let fake = ProviderConfig(
            id: "deepseek",
            apiKey: "",
            baseURL: nil,
            isEnabled: true,
            platformToken: "test-platform-token",
            platformCookie: nil
        )
        try? KeychainService.shared.save(fake)
    }

    override func tearDown() {
        MockURLProtocol.mockResponse = (data: nil, response: nil, error: nil)
        try? KeychainService.shared.delete(providerId: "deepseek")
        super.tearDown()
    }

    // MARK: - /usage/cost only (legacy coverage)

    func testFetchPlatformUsageParsesCostOnly() async throws {
        MockURLProtocol.requestHandler = { _ in
            (data: Self.costOnlyJSON.data(using: .utf8)!,
             response: HTTPURLResponse(url: URL(string: "https://platform.deepseek.com/api/v0/usage/cost?month=6&year=2026")!,
                                       statusCode: 200, httpVersion: nil, headerFields: nil)!,
             error: nil)
        }

        let usage = try await provider.fetchPlatformUsage(month: 6, year: 2026)
        XCTAssertEqual(usage.currency, "CNY")
        XCTAssertEqual(usage.year, 2026)
        XCTAssertEqual(usage.month, 6)
        XCTAssertFalse(usage.dailyUsage.isEmpty)
        XCTAssertFalse(usage.modelTotals.isEmpty)

        // All cost fields populated, all token fields zero (amount endpoint unreachable)
        for day in usage.dailyUsage {
            XCTAssertGreaterThanOrEqual(day.totalCost, 0)
            XCTAssertEqual(day.requestCount, 0)
            XCTAssertEqual(day.totalTokens, 0)
        }
        XCTAssertEqual(usage.totalRequests, 0)
        XCTAssertEqual(usage.totalTokens, 0)
    }

    // MARK: - /usage/amount only

    func testFetchPlatformUsageParsesAmountOnly() async throws {
        MockURLProtocol.requestHandler = { _ in
            (data: Self.amountOnlyJSON.data(using: .utf8)!,
             response: HTTPURLResponse(url: URL(string: "https://platform.deepseek.com/api/v0/usage/amount?month=6&year=2026")!,
                                       statusCode: 200, httpVersion: nil, headerFields: nil)!,
             error: nil)
        }

        let usage = try await provider.fetchPlatformUsage(month: 6, year: 2026)
        XCTAssertEqual(usage.currency, "CNY")  // defaults when cost endpoint unreachable
        XCTAssertFalse(usage.dailyUsage.isEmpty)

        // Cost endpoint unreachable → all cost fields are zero; token fields populated.
        for day in usage.dailyUsage {
            XCTAssertEqual(day.totalCost, 0)
        }

        // Real amounts from the fixture
        guard let day = usage.dailyUsage.first(where: { $0.date == "2026-06-13" }) else {
            return XCTFail("2026-06-13 missing")
        }
        XCTAssertEqual(day.requestCount, 201)        // 196 pro + 5 flash
        XCTAssertEqual(day.promptCacheHitTokens, 27_557_120)
        XCTAssertEqual(day.responseTokens, 92_096)    // 90461 + 1635
        XCTAssertGreaterThan(day.totalTokens, 0)
    }

    // MARK: - Both endpoints merged (the realistic scenario)

    func testFetchPlatformUsageMergesCostAndAmount() async throws {
        MockURLProtocol.requestHandler = { request in
            let urlString = request.url?.absoluteString ?? ""
            let body: String
            if urlString.contains("/usage/cost") {
                body = Self.costOnlyJSON
            } else if urlString.contains("/usage/amount") {
                body = Self.amountOnlyJSON
            } else {
                XCTFail("Unexpected URL: \(urlString)")
                return (Data(), HTTPURLResponse(), nil)
            }
            let url = URL(string: urlString)!
            return (data: body.data(using: .utf8)!,
                    response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    error: nil)
        }

        let usage = try await provider.fetchPlatformUsage(month: 6, year: 2026)
        XCTAssertEqual(usage.currency, "CNY")

        // 2026-06-13 must have BOTH cost and token data populated.
        guard let day = usage.dailyUsage.first(where: { $0.date == "2026-06-13" }) else {
            return XCTFail("2026-06-13 missing")
        }
        XCTAssertGreaterThan(day.totalCost, 0, "cost data should be present")
        XCTAssertGreaterThan(day.totalTokens, 0, "token data should be present")
        XCTAssertGreaterThan(day.requestCount, 0, "request data should be present")

        // /usage/cost values (per the cost fixture, 2026-06-13):
        //   pro: HIT 0.688928, MISS 1.532319, RESP 0.542766
        //   flash: MISS 0.000814, RESP 0.003270
        XCTAssertEqual(day.promptCacheHitCost, 0.688928, accuracy: 0.0001)
        XCTAssertEqual(day.promptCacheMissCost, 1.533133, accuracy: 0.0001)
        XCTAssertEqual(day.responseCost, 0.546036, accuracy: 0.0001)

        // /usage/amount values for the same day:
        //   pro: HIT 27_557_120, MISS 510_773, RESP 90_461, REQUEST 196
        //   flash: MISS 814, RESP 1_635, REQUEST 5
        XCTAssertEqual(day.promptCacheHitTokens, 27_557_120)
        XCTAssertEqual(day.requestCount, 201)

        // Per-model breakdown must carry BOTH metrics.
        guard let pro = day.modelBreakdown.first(where: { $0.modelName == "deepseek-v4-pro" }) else {
            return XCTFail("deepseek-v4-pro missing from breakdown")
        }
        XCTAssertGreaterThan(pro.totalCost, 0)
        XCTAssertGreaterThan(pro.totalTokens, 0)
        XCTAssertGreaterThan(pro.requestCount, 0)

        // Model totals also merge.
        XCTAssertEqual(usage.modelTotals.count, 2)
        let proTotal = try XCTUnwrap(usage.modelTotals.first(where: { $0.modelName == "deepseek-v4-pro" }))
        XCTAssertEqual(proTotal.promptCacheHitCost, 0.715894, accuracy: 0.0001)
        XCTAssertEqual(proTotal.promptCacheHitTokens, 28_635_776)
        XCTAssertEqual(proTotal.requestCount, 242)
    }

    func testFetchPlatformUsageThrowsWhenBothEndpointsFail() async throws {
        MockURLProtocol.requestHandler = { _ in
            (data: Data(),
             response: HTTPURLResponse(url: URL(string: "https://platform.deepseek.com")!,
                                       statusCode: 500, httpVersion: nil, headerFields: nil)!,
             error: nil)
        }

        do {
            _ = try await provider.fetchPlatformUsage(month: 6, year: 2026)
            XCTFail("Should throw when both endpoints fail")
        } catch TokenProviderError.serverError {
            // expected (cost endpoint fails first; both error paths funnel here)
        } catch TokenProviderError.invalidResponse {
            // also acceptable (depends on which endpoint fails first)
        }
    }

    // MARK: - Fixtures (mirror real API responses)

    private static let costOnlyJSON = """
    {
      "code": 0,
      "msg": "success",
      "data": {
        "biz_code": 0,
        "biz_data": [
          {
            "currency": "CNY",
            "days": [
              {
                "date": "2026-06-13",
                "data": [
                  {
                    "model": "deepseek-v4-pro",
                    "usage": [
                      {"type": "PROMPT_TOKEN", "amount": "0"},
                      {"type": "PROMPT_CACHE_HIT_TOKEN", "amount": "0.688928"},
                      {"type": "PROMPT_CACHE_MISS_TOKEN", "amount": "1.532319"},
                      {"type": "RESPONSE_TOKEN", "amount": "0.542766"},
                      {"type": "REQUEST", "amount": "0"}
                    ]
                  },
                  {
                    "model": "deepseek-v4-flash",
                    "usage": [
                      {"type": "PROMPT_TOKEN", "amount": "0"},
                      {"type": "PROMPT_CACHE_HIT_TOKEN", "amount": "0"},
                      {"type": "PROMPT_CACHE_MISS_TOKEN", "amount": "0.000814"},
                      {"type": "RESPONSE_TOKEN", "amount": "0.003270"},
                      {"type": "REQUEST", "amount": "0"}
                    ]
                  }
                ]
              }
            ],
            "total": [
              {
                "model": "deepseek-v4-pro",
                "usage": [
                  {"type": "PROMPT_TOKEN", "amount": "0"},
                  {"type": "PROMPT_CACHE_HIT_TOKEN", "amount": "0.715894"},
                  {"type": "PROMPT_CACHE_MISS_TOKEN", "amount": "2.590161"},
                  {"type": "RESPONSE_TOKEN", "amount": "0.727284"},
                  {"type": "REQUEST", "amount": "0"}
                ]
              },
              {
                "model": "deepseek-v4-flash",
                "usage": [
                  {"type": "PROMPT_TOKEN", "amount": "0"},
                  {"type": "PROMPT_CACHE_HIT_TOKEN", "amount": "0"},
                  {"type": "PROMPT_CACHE_MISS_TOKEN", "amount": "0.001232"},
                  {"type": "RESPONSE_TOKEN", "amount": "0.004014"},
                  {"type": "REQUEST", "amount": "0"}
                ]
              }
            ]
          }
        ]
      }
    }
    """

    private static let amountOnlyJSON = """
    {
      "code": 0,
      "msg": "",
      "data": {
        "biz_code": 0,
        "biz_msg": "",
        "biz_data": {
          "days": [
            {
              "date": "2026-06-13",
              "data": [
                {
                  "model": "deepseek-v4-pro",
                  "usage": [
                    {"type": "PROMPT_TOKEN", "amount": "0"},
                    {"type": "PROMPT_CACHE_HIT_TOKEN", "amount": "27557120"},
                    {"type": "PROMPT_CACHE_MISS_TOKEN", "amount": "510773"},
                    {"type": "RESPONSE_TOKEN", "amount": "90461"},
                    {"type": "REQUEST", "amount": "196"}
                  ]
                },
                {
                  "model": "deepseek-v4-flash",
                  "usage": [
                    {"type": "PROMPT_TOKEN", "amount": "0"},
                    {"type": "PROMPT_CACHE_HIT_TOKEN", "amount": "0"},
                    {"type": "PROMPT_CACHE_MISS_TOKEN", "amount": "814"},
                    {"type": "RESPONSE_TOKEN", "amount": "1635"},
                    {"type": "REQUEST", "amount": "5"}
                  ]
                }
              ]
            }
          ],
          "total": [
            {
              "model": "deepseek-v4-pro",
              "usage": [
                {"type": "PROMPT_TOKEN", "amount": "0"},
                {"type": "PROMPT_CACHE_HIT_TOKEN", "amount": "28635776"},
                {"type": "PROMPT_CACHE_MISS_TOKEN", "amount": "863387"},
                {"type": "RESPONSE_TOKEN", "amount": "121214"},
                {"type": "REQUEST", "amount": "242"}
              ]
            },
            {
              "model": "deepseek-v4-flash",
              "usage": [
                {"type": "PROMPT_TOKEN", "amount": "0"},
                {"type": "PROMPT_CACHE_HIT_TOKEN", "amount": "0"},
                {"type": "PROMPT_CACHE_MISS_TOKEN", "amount": "1232"},
                {"type": "RESPONSE_TOKEN", "amount": "2007"},
                {"type": "REQUEST", "amount": "7"}
              ]
            }
          ]
        }
      }
    }
    """
}