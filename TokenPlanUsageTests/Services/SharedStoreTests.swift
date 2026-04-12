import XCTest
@testable import TokenPlanUsage

final class SharedStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        SharedStore.shared.clearSnapshot()
        SharedStore.shared.clearDistribution()
    }

    func testSaveAndLoadSnapshot() {
        let snapshot = UsageSnapshot(
            providerId: "test",
            planName: "Test",
            usedCount: 10,
            totalCount: 100,
            remainingPercent: 0.9,
            refreshTime: nil,
            fetchedAt: Date(timeIntervalSince1970: 1000),
            status: .normal
        )

        SharedStore.shared.save(snapshot: snapshot)
        let loaded = SharedStore.shared.loadSnapshot()

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.providerId, "test")
        XCTAssertEqual(loaded?.usedCount, 10)
        XCTAssertEqual(loaded?.totalCount, 100)
        XCTAssertEqual(loaded!.remainingPercent, 0.9, accuracy: 0.001)
    }

    func testSaveAndLoadDistribution() {
        let distribution = UsageDistribution(
            providerId: "test",
            windowStart: Date(timeIntervalSince1970: 0),
            windowEnd: Date(timeIntervalSince1970: 3600),
            points: [UsagePoint(time: Date(timeIntervalSince1970: 0), count: 5)]
        )

        SharedStore.shared.save(distribution: distribution)
        let loaded = SharedStore.shared.loadDistribution()

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.providerId, "test")
        XCTAssertEqual(loaded?.points.count, 1)
        XCTAssertEqual(loaded?.points[0].count, 5)
    }

    func testClearSnapshot() {
        let snapshot = UsageSnapshot(
            providerId: "test",
            planName: "Test",
            usedCount: 10,
            totalCount: 100,
            remainingPercent: 0.9,
            refreshTime: nil,
            fetchedAt: Date(timeIntervalSince1970: 1000),
            status: .normal
        )

        SharedStore.shared.save(snapshot: snapshot)
        XCTAssertNotNil(SharedStore.shared.loadSnapshot())

        SharedStore.shared.clearSnapshot()
        XCTAssertNil(SharedStore.shared.loadSnapshot())
    }

    func testClearDistribution() {
        let distribution = UsageDistribution(
            providerId: "test",
            windowStart: Date(timeIntervalSince1970: 0),
            windowEnd: Date(timeIntervalSince1970: 3600),
            points: [UsagePoint(time: Date(timeIntervalSince1970: 0), count: 5)]
        )

        SharedStore.shared.save(distribution: distribution)
        XCTAssertNotNil(SharedStore.shared.loadDistribution())

        SharedStore.shared.clearDistribution()
        XCTAssertNil(SharedStore.shared.loadDistribution())
    }

    func testSaveAndLoadMultipleSnapshots() {
        let snapshot1 = UsageSnapshot(
            providerId: "provider1",
            planName: "P1",
            usedCount: 5,
            totalCount: 50,
            remainingPercent: 0.9,
            refreshTime: nil,
            fetchedAt: Date(timeIntervalSince1970: 1000),
            status: .normal
        )

        let snapshot2 = UsageSnapshot(
            providerId: "provider2",
            planName: "P2",
            usedCount: 15,
            totalCount: 150,
            remainingPercent: 0.9,
            refreshTime: nil,
            fetchedAt: Date(timeIntervalSince1970: 2000),
            status: .normal
        )

        SharedStore.shared.save(snapshot: snapshot1)
        SharedStore.shared.save(snapshot: snapshot2)

        let loaded1 = SharedStore.shared.loadSnapshot()
        XCTAssertNotNil(loaded1)
        XCTAssertEqual(loaded1?.providerId, "provider2", "Last saved snapshot should be loaded")

        SharedStore.shared.clearSnapshot()
        XCTAssertNil(SharedStore.shared.loadSnapshot())
    }
}
