import XCTest
@testable import TokenPlanUsage

@MainActor
final class MonitorViewModelTests: XCTestCase {

    var vm: MonitorViewModel!
    var mockProvider: MockTokenProvider!
    var mockConfig: ProviderConfig!

    override func setUp() async throws {
        try await super.setUp()
        mockProvider = MockTokenProvider()
        mockProvider.mockSnapshot = UsageSnapshot(
            providerId: "mock", planName: "Test",
            usedCount: 10, totalCount: 100,
            remainingPercent: 0.9, refreshTime: nil,
            fetchedAt: Date(timeIntervalSince1970: 1000), status: .normal, mcpQuota: nil, modelQuotas: nil
        )
        mockProvider.mockDistribution = UsageDistribution(
            providerId: "mock",
            windowStart: Date(timeIntervalSince1970: 0),
            windowEnd: Date(timeIntervalSince1970: 3600),
            points: [UsagePoint(time: Date(timeIntervalSince1970: 0), count: 5)]
        )
        mockConfig = ProviderConfig(id: "mock", apiKey: "test-key", baseURL: nil, isEnabled: true)
        vm = MonitorViewModel(provider: mockProvider, config: mockConfig)
    }

    func testRefreshUpdatesSnapshot() async throws {
        do {
            try KeychainService.shared.save(mockConfig)
        } catch KeychainService.KeychainError.additionFailed {
            throw XCTSkip("Keychain unavailable in test runner")
        }
        await vm.refresh()
        XCTAssertNotNil(vm.snapshot)
        XCTAssertEqual(vm.snapshot?.usedCount, 10)
        XCTAssertEqual(vm.snapshot?.totalCount, 100)
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.errorMessage)
    }

    func testRefreshSetsErrorState() async throws {
        do {
            try KeychainService.shared.save(mockConfig)
        } catch KeychainService.KeychainError.additionFailed {
            throw XCTSkip("Keychain unavailable in test runner")
        }
        mockProvider.shouldThrow = true
        await vm.refresh()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.errorMessage?.contains("API Key") ?? false)
    }

    func testRefreshPersistsToSharedStore() async throws {
        do {
            try KeychainService.shared.save(mockConfig)
        } catch KeychainService.KeychainError.additionFailed {
            throw XCTSkip("Keychain unavailable in test runner")
        }
        await vm.refresh()

        let loaded = SharedStore.shared.loadSnapshot(providerId: "mock")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.usedCount, 10)
    }

    func testLoadingState() async throws {
        XCTAssertFalse(vm.isLoading)
        await vm.refresh()
        XCTAssertFalse(vm.isLoading)
    }

    func testInitialLoadFromSharedStore() throws {
        let snapshot = UsageSnapshot(
            providerId: "mock", planName: "Test",
            usedCount: 20, totalCount: 200,
            remainingPercent: 0.9, refreshTime: nil,
            fetchedAt: Date(timeIntervalSince1970: 2000), status: .normal, mcpQuota: nil, modelQuotas: nil
        )
        SharedStore.shared.save(snapshot: snapshot)

        let vm = MonitorViewModel(provider: MockTokenProvider(), config: mockConfig)
        XCTAssertEqual(vm.snapshot?.usedCount, 20)
    }

    // MARK: - Monthly trend (DeepSeek)

    func testRefreshMonthlyTrendAggregatesPastSixMonths() async throws {
        let provider = DeepSeekProvider()
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        provider.urlSession = URLSession(configuration: sessionConfig)

        let deepseekConfig = ProviderConfig(
            id: "deepseek",
            apiKey: "",
            baseURL: nil,
            isEnabled: true,
            platformToken: "test-platform-token",
            platformCookie: nil
        )
        try KeychainService.shared.save(deepseekConfig)
        defer {
            try? KeychainService.shared.delete(providerId: "deepseek")
            MockURLProtocol.requestHandler = nil
        }

        // Each call to /usage/cost returns the same 10.0 CNY response, regardless
        // of the month — the test just verifies the aggregator fans out and
        // produces 6 points. The amount endpoint is stubbed to return an empty
        // (but valid) payload so fetchPlatformUsage does not throw.
        let costJSON = """
        {
          "code": 0,
          "data": {
            "biz_code": 0,
            "biz_data": [{
              "currency": "CNY",
              "days": [{
                "date": "2026-01-15",
                "data": [{
                  "model": "deepseek-v4-pro",
                  "usage": [{"type": "RESPONSE_TOKEN", "amount": "10.0"}]
                }]
              }],
              "total": []
            }]
          }
        }
        """
        let amountJSON = """
        {
          "code": 0,
          "data": {
            "biz_code": 0,
            "biz_data": {"days": [], "total": []}
          }
        }
        """
        MockURLProtocol.requestHandler = { request in
            let urlString = request.url?.absoluteString ?? ""
            let url = URL(string: urlString)!
            let body = urlString.contains("/usage/cost") ? costJSON : amountJSON
            return (data: body.data(using: .utf8)!,
                    response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    error: nil)
        }

        let vm = MonitorViewModel(provider: provider, config: deepseekConfig)
        await vm.refreshMonthlyTrend()

        XCTAssertEqual(vm.monthlyTrend.count, 6, "expected one point per month in the past-6 window")
        XCTAssertFalse(vm.isMonthlyTrendLoading)
        XCTAssertTrue(vm.monthlyTrend.allSatisfy { $0.consumption == 10.0 && $0.currency == "CNY" })
        for i in 1..<vm.monthlyTrend.count {
            XCTAssertLessThan(vm.monthlyTrend[i - 1].month, vm.monthlyTrend[i].month,
                              "trend must be sorted ascending by month")
        }
    }

    func testRefreshMonthlyTrendSkipsFailedMonths() async throws {
        let provider = DeepSeekProvider()
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        provider.urlSession = URLSession(configuration: sessionConfig)

        let deepseekConfig = ProviderConfig(
            id: "deepseek",
            apiKey: "",
            baseURL: nil,
            isEnabled: true,
            platformToken: "test-platform-token",
            platformCookie: nil
        )
        try KeychainService.shared.save(deepseekConfig)
        defer {
            try? KeychainService.shared.delete(providerId: "deepseek")
            MockURLProtocol.requestHandler = nil
        }

        // The "current" month fails on BOTH endpoints, so fetchPlatformUsage
        // throws and the month is skipped. Older months succeed normally.
        let now = Date()
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)

        let costJSON = """
        {
          "code": 0,
          "data": {
            "biz_code": 0,
            "biz_data": [{
              "currency": "CNY",
              "days": [{
                "date": "2026-01-15",
                "data": [{
                  "model": "deepseek-v4-pro",
                  "usage": [{"type": "RESPONSE_TOKEN", "amount": "5.0"}]
                }]
              }],
              "total": []
            }]
          }
        }
        """
        let amountJSON = """
        {
          "code": 0,
          "data": {
            "biz_code": 0,
            "biz_data": {"days": [], "total": []}
          }
        }
        """
        MockURLProtocol.requestHandler = { request in
            let urlString = request.url?.absoluteString ?? ""
            let url = URL(string: urlString)!
            let isCurrentMonth = urlString.contains("month=\(currentMonth)&year=\(currentYear)")
            if isCurrentMonth {
                return (data: Data(),
                        response: HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                        error: nil)
            }
            let body = urlString.contains("/usage/cost") ? costJSON : amountJSON
            return (data: body.data(using: .utf8)!,
                    response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    error: nil)
        }

        let vm = MonitorViewModel(provider: provider, config: deepseekConfig)
        await vm.refreshMonthlyTrend()

        XCTAssertEqual(vm.monthlyTrend.count, 5, "current month (both endpoints failing) should be skipped")
        XCTAssertTrue(vm.monthlyTrend.allSatisfy { $0.consumption == 5.0 })
    }

    func testRefreshMonthlyTrendWithoutTokenStaysEmpty() async throws {
        // DeepSeek provider with no platform token → refreshMonthlyTrend must
        // short-circuit and leave the trend empty.
        let provider = DeepSeekProvider()
        try KeychainService.shared.delete(providerId: "deepseek")

        let config = ProviderConfig(id: "deepseek", apiKey: "", baseURL: nil, isEnabled: true)
        let vm = MonitorViewModel(provider: provider, config: config)
        await vm.refreshMonthlyTrend()

        XCTAssertTrue(vm.monthlyTrend.isEmpty)
        XCTAssertFalse(vm.isMonthlyTrendLoading)
    }
}
