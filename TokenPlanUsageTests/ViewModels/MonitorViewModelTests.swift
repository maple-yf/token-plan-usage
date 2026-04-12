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
        await vm.refresh()
        XCTAssertNotNil(vm.snapshot)
        XCTAssertEqual(vm.snapshot?.usedCount, 10)
        XCTAssertEqual(vm.snapshot?.totalCount, 100)
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.errorMessage)
    }

    func testRefreshSetsErrorState() async {
        mockProvider.shouldThrow = true
        await vm.refresh()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.errorMessage?.contains("API Key") ?? false)
    }

    func testRefreshPersistsToSharedStore() async throws {
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
}
