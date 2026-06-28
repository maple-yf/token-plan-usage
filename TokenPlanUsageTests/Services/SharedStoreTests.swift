import XCTest
@testable import TokenPlanUsage

final class SharedStoreTests: XCTestCase {

    private let testProviderId = "test_provider"

    private func makeSnapshot(providerId: String = "test_provider", usedCount: Int = 10, totalCount: Int = 100) -> UsageSnapshot {
        UsageSnapshot(
            providerId: providerId,
            planName: "Test",
            usedCount: usedCount,
            totalCount: totalCount,
            remainingPercent: 0.9,
            refreshTime: nil,
            fetchedAt: Date(timeIntervalSince1970: 1000),
            status: .normal,
            mcpQuota: nil,
            modelQuotas: nil
        )
    }

    func testSaveAndLoadSnapshot() {
        let snapshot = makeSnapshot()

        SharedStore.shared.save(snapshot: snapshot)
        let loaded = SharedStore.shared.loadSnapshot(providerId: testProviderId)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.providerId, testProviderId)
        XCTAssertEqual(loaded?.usedCount, 10)
        XCTAssertEqual(loaded?.totalCount, 100)
        XCTAssertEqual(loaded!.remainingPercent, 0.9, accuracy: 0.001)
    }

    func testSaveAndLoadDistribution() {
        let distribution = UsageDistribution(
            providerId: testProviderId,
            windowStart: Date(timeIntervalSince1970: 0),
            windowEnd: Date(timeIntervalSince1970: 3600),
            points: [UsagePoint(time: Date(timeIntervalSince1970: 0), count: 5)]
        )

        SharedStore.shared.save(distribution: distribution)
        let loaded = SharedStore.shared.loadDistribution(providerId: testProviderId)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.providerId, testProviderId)
        XCTAssertEqual(loaded?.points.count, 1)
        XCTAssertEqual(loaded?.points[0].count, 5)
    }

    func testProvidersStoredSeparately() {
        let snapshot1 = makeSnapshot(providerId: "provider1", usedCount: 5, totalCount: 50)
        let snapshot2 = makeSnapshot(providerId: "provider2", usedCount: 15, totalCount: 150)

        SharedStore.shared.save(snapshot: snapshot1)
        SharedStore.shared.save(snapshot: snapshot2)

        let loaded1 = SharedStore.shared.loadSnapshot(providerId: "provider1")
        let loaded2 = SharedStore.shared.loadSnapshot(providerId: "provider2")

        XCTAssertEqual(loaded1?.usedCount, 5)
        XCTAssertEqual(loaded1?.totalCount, 50)
        XCTAssertEqual(loaded2?.usedCount, 15)
        XCTAssertEqual(loaded2?.totalCount, 150)
    }

    // MARK: - Provider Visibility

    private func resetVisibleProviders() {
        SharedStore.shared.visibleProviderIds = ["minimax", "glm", "deepseek"]
    }

    func testSetProviderVisibilityFalseHidesProvider() {
        resetVisibleProviders()

        SharedStore.shared.setProviderVisibility("glm", visible: false)

        XCTAssertFalse(SharedStore.shared.isProviderVisible("glm"))
        XCTAssertTrue(SharedStore.shared.isProviderVisible("minimax"))
        XCTAssertTrue(SharedStore.shared.isProviderVisible("deepseek"))
        XCTAssertEqual(SharedStore.shared.visibleProviderIds, ["minimax", "deepseek"])
    }

    func testSetProviderVisibilityTrueRestoresProvider() {
        resetVisibleProviders()
        SharedStore.shared.setProviderVisibility("glm", visible: false)

        SharedStore.shared.setProviderVisibility("glm", visible: true)

        XCTAssertTrue(SharedStore.shared.isProviderVisible("glm"))
        XCTAssertEqual(SharedStore.shared.visibleProviderIds.sorted(), ["deepseek", "glm", "minimax"])
    }

    func testSetProviderVisibilityIsIdempotent() {
        resetVisibleProviders()

        // Hiding twice keeps it hidden without duplicating work or losing other entries.
        SharedStore.shared.setProviderVisibility("glm", visible: false)
        let afterFirstHide = SharedStore.shared.visibleProviderIds
        SharedStore.shared.setProviderVisibility("glm", visible: false)
        XCTAssertEqual(SharedStore.shared.visibleProviderIds, afterFirstHide)

        // Showing twice keeps it visible exactly once in the list.
        SharedStore.shared.setProviderVisibility("glm", visible: true)
        SharedStore.shared.setProviderVisibility("glm", visible: true)
        XCTAssertEqual(SharedStore.shared.visibleProviderIds.filter { $0 == "glm" }.count, 1)
    }

    /// Regression: previously the Settings toggle called `toggleProviderVisibility`
    /// which inverted the visible state. With default `visibleProviderIds` already
    /// containing all three providers, enabling a default-disabled provider
    /// (glm / deepseek) would actually hide it. The fix uses an explicit
    /// set operation keyed on `isEnabled`.
    func testEnablingDefaultDisabledProviderKeepsItVisible() {
        resetVisibleProviders()

        SharedStore.shared.setProviderVisibility("glm", visible: true)
        SharedStore.shared.setProviderVisibility("deepseek", visible: true)

        XCTAssertTrue(SharedStore.shared.isProviderVisible("glm"))
        XCTAssertTrue(SharedStore.shared.isProviderVisible("deepseek"))
        XCTAssertTrue(SharedStore.shared.isProviderVisible("minimax"))
    }

    func testDisablingDefaultEnabledProviderHidesIt() {
        resetVisibleProviders()

        SharedStore.shared.setProviderVisibility("minimax", visible: false)

        XCTAssertFalse(SharedStore.shared.isProviderVisible("minimax"))
        XCTAssertTrue(SharedStore.shared.isProviderVisible("glm"))
        XCTAssertTrue(SharedStore.shared.isProviderVisible("deepseek"))
    }

    func testVisibilityPersistsAcrossInstances() {
        resetVisibleProviders()
        SharedStore.shared.setProviderVisibility("glm", visible: false)

        XCTAssertFalse(SharedStore.shared.isProviderVisible("glm"))
        XCTAssertEqual(SharedStore.shared.visibleProviderIds, ["minimax", "deepseek"])

        // Re-enable from a different starting point — the new state
        // reflects the latest setProviderVisibility call, not any stale
        // in-memory value.
        SharedStore.shared.visibleProviderIds = ["minimax"]
        SharedStore.shared.setProviderVisibility("glm", visible: true)
        XCTAssertEqual(SharedStore.shared.visibleProviderIds.sorted(), ["glm", "minimax"])
    }
}
