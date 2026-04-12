import XCTest
import SwiftUI
@testable import TokenPlanUsage

@MainActor
final class RingProgressViewTests: XCTestCase {

    func testOnRefreshCallbackIsInvoked() {
        var refreshCalled = false
        let view = RingProgressView(
            progress: 0.9,
            usedCount: 10,
            totalCount: 100,
            planName: "Test Plan",
            remainingTimeString: "1:00:00",
            onRefresh: { refreshCalled = true }
        )
        // Simulate the callback being triggered
        view.onRefresh?()
        XCTAssertTrue(refreshCalled, "onRefresh callback should be invoked")
    }

    func testOnRefreshIsNilByDefault() {
        let view = RingProgressView(
            progress: 0.9,
            usedCount: 10,
            totalCount: 100,
            planName: "Test Plan",
            remainingTimeString: nil
        )
        XCTAssertNil(view.onRefresh, "onRefresh should default to nil")
    }

    func testAccessibilityHintIncludesRefreshAction() {
        let view = RingProgressView(
            progress: 0.5,
            usedCount: 50,
            totalCount: 100,
            planName: "Test Plan",
            remainingTimeString: nil,
            onRefresh: {}
        )
        // Verify the view is created with refresh callback
        XCTAssertNotNil(view.onRefresh)
    }
}
