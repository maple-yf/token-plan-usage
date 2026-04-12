import XCTest
@testable import TokenPlanUsage

final class UsageSnapshotTests: XCTestCase {

    func testEncodeDecode() throws {
        let snapshot = UsageSnapshot(
            providerId: "minimax",
            planName: "MiniMax-M2.7",
            usedCount: 25,
            totalCount: 600,
            remainingPercent: 0.958,
            refreshTime: Date(timeIntervalSince1970: 1713000000),
            fetchedAt: Date(timeIntervalSince1970: 1712990000),
            status: .normal,
            mcpQuota: nil,
            modelQuotas: nil
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: data)
        XCTAssertEqual(decoded.providerId, "minimax")
        XCTAssertEqual(decoded.usedCount, 25)
        XCTAssertEqual(decoded.totalCount, 600)
        XCTAssertEqual(decoded.remainingPercent, 0.958, accuracy: 0.001)
        XCTAssertEqual(decoded.status, .normal)
        XCTAssertNil(decoded.mcpQuota)
    }

    func testEncodeDecodeWithMCPQuota() throws {
        let snapshot = UsageSnapshot(
            providerId: "glm",
            planName: "GLM Coding Plan",
            usedCount: 0,
            totalCount: 0,
            remainingPercent: 0.99,
            refreshTime: nil,
            fetchedAt: Date(timeIntervalSince1970: 1713000000),
            status: .normal,
            mcpQuota: MCPQuota(usedCount: 3, totalCount: 1000, remainingCount: 997),
            modelQuotas: nil
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: data)
        XCTAssertNotNil(decoded.mcpQuota)
        XCTAssertEqual(decoded.mcpQuota?.usedCount, 3)
        XCTAssertEqual(decoded.mcpQuota?.totalCount, 1000)
        XCTAssertEqual(decoded.mcpQuota?.remainingCount, 997)
    }

    func testAPIStatusNormal() throws {
        let status: APIStatus = .normal
        let data = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(APIStatus.self, from: data)
        XCTAssertEqual(decoded, .normal)
    }

    func testAPIStatusError() throws {
        let status: APIStatus = .error("unauthorized")
        let data = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(APIStatus.self, from: data)
        if case .error(let msg) = decoded {
            XCTAssertEqual(msg, "unauthorized")
        } else {
            XCTFail("Expected error status")
        }
    }

    func testProviderConfigDefaults() {
        XCTAssertEqual(ProviderConfig.minimax.id, "minimax")
        XCTAssertTrue(ProviderConfig.minimax.isEnabled)
        XCTAssertEqual(ProviderConfig.glm.id, "glm")
        XCTAssertFalse(ProviderConfig.glm.isEnabled)
    }

    func testUsagePointIdentifiable() {
        let date = Date(timeIntervalSince1970: 1000)
        let point = UsagePoint(time: date, count: 5)
        XCTAssertEqual(point.id, date)
        XCTAssertEqual(point.count, 5)
    }
}
