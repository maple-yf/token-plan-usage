# Token Plan Usage iOS App — Implementation Plan

> **For implementer:** Use TDD throughout. Write failing test first. Watch it fail. Then implement.

**Goal:** Build an iOS App that monitors MiniMax and GLM API token usage with a glassmorphism UI, supporting custom base URLs and home screen widgets.

**Architecture:** MVVM with SwiftUI. Single app target + Widget extension. Data shared via App Group. API Key stored in Keychain. Provider logic behind a protocol for extensibility.

**Tech Stack:** SwiftUI, Swift Charts, WidgetKit, KeychainAccess, iOS 17+

---

## Phase 1: Project Scaffold & Data Models

### Task 1: Create Xcode Project

**Files:**
- Create: `TokenPlanUsage.xcodeproj` (via Xcode or `xcodegen`)
- Create: `TokenPlanUsage/App/TokenPlanUsageApp.swift`
- Create: `TokenPlanUsage/Info.plist`

**Step 1: Scaffold project**
- Create new iOS App project in Xcode: Product Name "TokenPlanUsage", Interface SwiftUI, Language Swift, Minimum Deployment iOS 17.0
- No Core Data, no tests target yet (we add later)

**Step 2: Verify build**
Command: `xcodebuild -scheme TokenPlanUsage -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: BUILD SUCCEEDED

**Step 3: Commit**
`git add . && git commit -m "feat: scaffold Xcode project"`

---

### Task 2: Define Data Models

**Files:**
- Create: `TokenPlanUsage/Models/ProviderConfig.swift`
- Create: `TokenPlanUsage/Models/UsageSnapshot.swift`
- Create: `TokenPlanUsage/Models/UsageDistribution.swift`
- Create: `TokenPlanUsage/Models/APIStatus.swift`
- Create: `TokenPlanUsageTests/Models/UsageSnapshotTests.swift`

**Step 1: Write the failing test**
```swift
// TokenPlanUsageTests/Models/UsageSnapshotTests.swift
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
            status: .normal
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: data)
        XCTAssertEqual(decoded.providerId, "minimax")
        XCTAssertEqual(decoded.usedCount, 25)
        XCTAssertEqual(decoded.totalCount, 600)
        XCTAssertEqual(decoded.remainingPercent, 0.958)
    }

    func testAPIStatusEncodeDecode() throws {
        let normal = APIStatus.normal
        let data = try JSONEncoder().encode(normal)
        let decoded = try JSONDecoder().decode(APIStatus.self, from: data)
        XCTAssertEqual(decoded, .normal)

        let error = APIStatus.error("unauthorized")
        let data2 = try JSONEncoder().encode(error)
        let decoded2 = try JSONDecoder().decode(APIStatus.self, from: data2)
        if case .error(let msg) = decoded2 {
            XCTAssertEqual(msg, "unauthorized")
        } else {
            XCTFail("Expected error status")
        }
    }
}
```

**Step 2: Run test — confirm it fails**
Command: `xcodebuild test -scheme TokenPlanUsage -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TokenPlanUsageTests/UsageSnapshotTests`
Expected: FAIL — "Cannot find 'UsageSnapshot' in scope"

**Step 3: Write implementation**
```swift
// TokenPlanUsage/Models/APIStatus.swift
import Foundation

enum APIStatus: Codable, Equatable {
    case normal
    case error(String)
}

// TokenPlanUsage/Models/ProviderConfig.swift
import Foundation

struct ProviderConfig: Codable, Identifiable, Equatable {
    let id: String  // "minimax" | "glm"
    var apiKey: String
    var baseURL: String?
    var isEnabled: Bool

    static let minimax = ProviderConfig(id: "minimax", apiKey: "", baseURL: nil, isEnabled: true)
    static let glm = ProviderConfig(id: "glm", apiKey: "", baseURL: nil, isEnabled: false)
}

// TokenPlanUsage/Models/UsageSnapshot.swift
import Foundation

struct UsageSnapshot: Codable, Equatable {
    let providerId: String
    let planName: String
    let usedCount: Int
    let totalCount: Int
    let remainingPercent: Double
    let refreshTime: Date?
    let fetchedAt: Date
    let status: APIStatus
}

// TokenPlanUsage/Models/UsageDistribution.swift
import Foundation

struct UsageDistribution: Codable, Equatable {
    let providerId: String
    let windowStart: Date
    let windowEnd: Date
    let points: [UsagePoint]
}

struct UsagePoint: Codable, Identifiable, Equatable {
    var id: Date { time }
    let time: Date
    let count: Int
}
```

**Step 4: Run test — confirm it passes**
Command: same as above
Expected: PASS

**Step 5: Commit**
`git add . && git commit -m "feat: define data models with Codable support"`

---

## Phase 2: API Layer

### Task 3: Define TokenProvider Protocol

**Files:**
- Create: `TokenPlanUsage/Services/TokenProvider.swift`
- Create: `TokenPlanUsageTests/Services/MockTokenProvider.swift`

**Step 1: Write protocol and mock**
```swift
// TokenPlanUsage/Services/TokenProvider.swift
import Foundation

protocol TokenProvider {
    var id: String { get }
    var displayName: String { get }
    var defaultBaseURL: String { get }

    func fetchUsage(apiKey: String, baseURL: String?) async throws -> UsageSnapshot
    func fetchDistribution(apiKey: String, baseURL: String?) async throws -> UsageDistribution
}

enum TokenProviderError: LocalizedError {
    case invalidAPIKey
    case networkUnavailable
    case serverError(Int)
    case invalidResponse
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey: return "API Key 无效，请检查设置"
        case .networkUnavailable: return "网络不可用"
        case .serverError(let code): return "服务端错误 (\(code))"
        case .invalidResponse: return "响应格式异常"
        case .timeout: return "请求超时"
        }
    }
}
```

**Step 2: Write test with mock**
```swift
// TokenPlanUsageTests/Services/MockTokenProviderTests.swift
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
            remainingPercent: 0.9, refreshTime: nil, fetchedAt: Date(), status: .normal
        )
        let result = try await provider.fetchUsage(apiKey: "test", baseURL: nil)
        XCTAssertEqual(result.usedCount, 10)
    }

    func testFetchUsageThrows() async {
        let provider = MockTokenProvider()
        provider.shouldThrow = true
        do {
            _ = try await provider.fetchUsage(apiKey: "bad", baseURL: nil)
            XCTFail("Should have thrown")
        } catch {
            // expected
        }
    }
}
```

**Step 3: Run test — confirm passes**
Command: `xcodebuild test ...`
Expected: PASS

**Step 4: Commit**
`git add . && git commit -m "feat: define TokenProvider protocol with mock for testing"`

---

### Task 4: Implement MiniMax Provider

**Files:**
- Create: `TokenPlanUsage/Services/Providers/MiniMaxProvider.swift`
- Create: `TokenPlanUsageTests/Services/MiniMaxProviderTests.swift`

**Step 1: Write failing test with mock URLProtocol**
```swift
// TokenPlanUsageTests/Services/MiniMaxProviderTests.swift
import XCTest
@testable import TokenPlanUsage

class MockURLProtocol: URLProtocol {
    static var mockResponse: (data: Data?, response: HTTPURLResponse?, error: Error?)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let error = Self.mockResponse.error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            if let response = Self.mockResponse.response {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            if let data = Self.mockResponse.data {
                client?.urlProtocol(self, didLoad: data)
            }
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class MiniMaxProviderTests: XCTestCase {
    var provider: MiniMaxProvider!
    var session: URLSession!

    override func setUp() {
        provider = MiniMaxProvider()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        provider.urlSession = session
    }

    func testFetchUsageParsesCorrectly() async throws {
        // TODO: confirm actual MiniMax API response format, then write mock JSON
        // Placeholder: simulate a balance/usage response
        let json = """
        {
            "base_resp": {"status_code": 0, "status_msg": "success"},
            "data": {
                "total": 600,
                "used": 25,
                "plan_name": "MiniMax-M2.7"
            }
        }
        """.data(using: .utf8)!
        MockURLProtocol.mockResponse = (
            data: json,
            response: HTTPURLResponse(url: URL(string: "https://api.minimax.chat/v1/usage")!, statusCode: 200, httpVersion: nil, headerFields: nil),
            error: nil
        )
        let snapshot = try await provider.fetchUsage(apiKey: "test-key", baseURL: nil)
        XCTAssertEqual(snapshot.usedCount, 25)
        XCTAssertEqual(snapshot.totalCount, 600)
        XCTAssertEqual(snapshot.providerId, "minimax")
    }

    func testFetchUsageThrowsOn401() async {
        MockURLProtocol.mockResponse = (
            data: Data(),
            response: HTTPURLResponse(url: URL(string: "https://api.minimax.chat/v1/usage")!, statusCode: 401, httpVersion: nil, headerFields: nil),
            error: nil
        )
        do {
            _ = try await provider.fetchUsage(apiKey: "bad-key", baseURL: nil)
            XCTFail("Should throw")
        } catch TokenProviderError.invalidAPIKey {
            // expected
        }
    }
}
```

**Step 2: Run test — confirm it fails**
Expected: FAIL — MiniMaxProvider not found

**Step 3: Implement MiniMaxProvider**
```swift
// TokenPlanUsage/Services/Providers/MiniMaxProvider.swift
import Foundation

class MiniMaxProvider: TokenProvider {
    let id = "minimax"
    let displayName = "MiniMax"
    let defaultBaseURL = "https://api.minimax.chat"
    var urlSession: URLSession = .shared

    // NOTE: exact endpoint TBD — confirm from MiniMax docs during development
    // Possible endpoints:
    //   GET /v1/user/info
    //   GET /v1/usage/balance
    func fetchUsage(apiKey: String, baseURL: String?) async throws -> UsageSnapshot {
        let base = baseURL ?? defaultBaseURL
        guard let url = URL(string: "\(base)/v1/user/info") else {
            throw TokenProviderError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TokenProviderError.invalidResponse
        }
        if http.statusCode == 401 { throw TokenProviderError.invalidAPIKey }
        guard http.statusCode == 200 else {
            throw TokenProviderError.serverError(http.statusCode)
        }
        // Parse — structure TBD, will adjust based on actual API response
        return try parseUsageResponse(data, providerId: id)
    }

    func fetchDistribution(apiKey: String, baseURL: String?) async throws -> UsageDistribution {
        // v1: return empty distribution; detailed distribution requires per-provider investigation
        return UsageDistribution(
            providerId: id,
            windowStart: Date().addingTimeInterval(-5 * 3600),
            windowEnd: Date(),
            points: []
        )
    }

    private func parseUsageResponse(_ data: Data, providerId: String) throws -> UsageSnapshot {
        // Will be refined once actual API response format is confirmed
        struct Response: Decodable {
            let data: UsageData?
            struct UsageData: Decodable {
                let total: Int
                let used: Int
                let planName: String?
            }
        }
        let resp = try JSONDecoder().decode(Response.self, from: data)
        guard let usage = resp.data else { throw TokenProviderError.invalidResponse }
        let remaining = usage.total - usage.used
        let percent = usage.total > 0 ? Double(remaining) / Double(usage.total) : 0
        return UsageSnapshot(
            providerId: providerId,
            planName: usage.planName ?? "MiniMax",
            usedCount: usage.used,
            totalCount: usage.total,
            remainingPercent: percent,
            refreshTime: nil,
            fetchedAt: Date(),
            status: .normal
        )
    }
}
```

**Step 4: Run test — confirm it passes**

**Step 5: Commit**
`git add . && git commit -m "feat: implement MiniMax provider with mock URL tests"`

---

### Task 5: Implement GLM Provider

**Files:**
- Create: `TokenPlanUsage/Services/Providers/GLMProvider.swift`
- Create: `TokenPlanUsageTests/Services/GLMProviderTests.swift`

**Same pattern as Task 4.** Mock URLProtocol, test success/failure cases.

Key details:
- Base URL: `https://open.bigmodel.cn/api/paas/v4`
- Auth header: `Authorization: Bearer <api_key>`
- Balance endpoint: TBD (likely `/api/paas/v4/users/balance` or similar)
- Zhipu uses OpenAI-compatible API format

**Step 5: Commit**
`git add . && git commit -m "feat: implement GLM provider with mock URL tests"`

---

## Phase 3: Storage Layer

### Task 6: Keychain Service

**Files:**
- Create: `TokenPlanUsage/Services/KeychainService.swift`
- Create: `TokenPlanUsageTests/Services/KeychainServiceTests.swift`

**Step 1: Write failing test**
```swift
func testSaveAndLoadProviderConfig() throws {
    let service = KeychainService()
    let config = ProviderConfig(id: "minimax", apiKey: "sk-test123", baseURL: nil, isEnabled: true)
    try service.save(config)
    let loaded = service.load(providerId: "minimax")
    XCTAssertEqual(loaded?.apiKey, "sk-test123")
    // cleanup
    try service.delete(providerId: "minimax")
}
```

**Step 3: Implement KeychainService**
- Use Apple Security framework directly (no third-party dependency)
- Store one Keychain item per provider, keyed by `com.tokenplan.<providerId>`

**Step 5: Commit**
`git add . && git commit -m "feat: implement KeychainService for API key storage"`

---

### Task 7: App Group Shared Storage

**Files:**
- Create: `TokenPlanUsage/Services/SharedStore.swift`
- Create: `TokenPlanUsageTests/Services/SharedStoreTests.swift`

**Step 1: Write failing test**
Test save/load UsageSnapshot and UsageDistribution via UserDefaults(suiteName:).

**Step 3: Implement SharedStore**
- Use `UserDefaults(suiteName: "group.com.tokenplan.usage")` for snapshots
- Write/read JSON-encoded data
- Widget reads from same suite

**Step 5: Commit**
`git add . && git commit -m "feat: implement App Group shared storage for snapshots"`

---

## Phase 4: View Models

### Task 8: MonitorViewModel

**Files:**
- Create: `TokenPlanUsage/ViewModels/MonitorViewModel.swift`
- Create: `TokenPlanUsageTests/ViewModels/MonitorViewModelTests.swift`

**Step 1: Write failing test**
```swift
@MainActor
func testFetchUsageUpdatesSnapshot() async throws {
    let vm = MonitorViewModel(provider: MockTokenProvider())
    vm.mockSnapshot = UsageSnapshot(providerId: "mock", planName: "Test",
        usedCount: 10, totalCount: 100, remainingPercent: 0.9,
        refreshTime: nil, fetchedAt: Date(), status: .normal)
    try await vm.refresh()
    XCTAssertNotNil(vm.snapshot)
    XCTAssertEqual(vm.snapshot?.usedCount, 10)
    XCTAssertFalse(vm.isLoading)
}

@MainActor
func testFetchUsageSetsErrorState() async {
    let vm = MonitorViewModel(provider: FailingMockProvider())
    await vm.refresh()
    XCTAssertNil(vm.snapshot)
    XCTAssertNotNil(vm.errorMessage)
}
```

**Step 3: Implement MonitorViewModel**
```swift
@Observable
class MonitorViewModel {
    var snapshot: UsageSnapshot?
    var distribution: UsageDistribution?
    var isLoading = false
    var errorMessage: String?

    private let provider: TokenProvider
    private let config: ProviderConfig

    func refresh() async { ... }
    func selectProvider(_ id: String) { ... }
}
```

**Step 5: Commit**
`git add . && git commit -m "feat: implement MonitorViewModel with refresh logic"`

---

### Task 9: SettingsViewModel

**Files:**
- Create: `TokenPlanUsage/ViewModels/SettingsViewModel.swift`
- Create: `TokenPlanUsageTests/ViewModels/SettingsViewModelTests.swift`

Test save/load ProviderConfig, API Key trimming, Base URL validation.

**Step 5: Commit**
`git add . && git commit -m "feat: implement SettingsViewModel with validation"`

---

## Phase 5: UI — Monitor Page

### Task 10: RingProgressView

**Files:**
- Create: `TokenPlanUsage/Views/Monitor/RingProgressView.swift`

Custom `Shape` drawing an arc. Accepts `progress: Double` (0-1) and `color: Color`. Animate on value change.

No unit test (pure visual). Verify via `#Preview`.

**Commit**
`git add . && git commit -m "feat: implement ring progress view with animation"`

---

### Task 11: UsageTrendChart

**Files:**
- Create: `TokenPlanUsage/Views/Monitor/UsageTrendChart.swift`

Use `Swift Charts` `Chart` + `LineMark`. Accepts `[UsagePoint]`. Scrollable via `ScrollView` + `chartXScale`.

**Commit**
`git add . && git commit -m "feat: implement usage trend line chart"`

---

### Task 12: UsageDetailView

**Files:**
- Create: `TokenPlanUsage/Views/Monitor/UsageDetailView.swift`

3-column Grid: 已用次数 / 剩余次数 / 剩余时间. Glassmorphism card background.

**Commit**
`git add . && git commit -m "feat: implement usage detail grid view"`

---

### Task 13: StatusBar + Refresh Button

**Files:**
- Create: `TokenPlanUsage/Views/Monitor/StatusBarView.swift`

Green/red dot + API status text + last update time + refresh button (spinner when loading).

**Commit**
`git add . && git commit -m "feat: implement status bar with refresh button"`

---

### Task 14: MonitorView (Composition)

**Files:**
- Create: `TokenPlanUsage/Views/Monitor/MonitorView.swift`

Compose all components. ProviderSegmentControl at top. Bind to `MonitorViewModel`. Glassmorphism background.

**Commit**
`git add . && git commit -m "feat: compose monitor page with all components"`

---

## Phase 6: UI — Settings Page

### Task 15: ProviderConfigView

**Files:**
- Create: `TokenPlanUsage/Views/Settings/ProviderConfigView.swift`

Per-provider card: toggle enable, SecureField for API Key, Base URL picker (default / custom).

**Commit**
`git add . && git commit -m "feat: implement provider config view"`

---

### Task 16: SettingsView

**Files:**
- Create: `TokenPlanUsage/Views/Settings/SettingsView.swift`

List of ProviderConfigView + refresh interval picker + Widget provider picker.

**Commit**
`git add . && git commit -m "feat: compose settings page"`

---

## Phase 7: App Shell & Navigation

### Task 17: Main TabView + App Entry

**Files:**
- Modify: `TokenPlanUsage/App/TokenPlanUsageApp.swift`
- Create: `TokenPlanUsage/Views/MainTabView.swift`

Two-tab TabView: Monitor + Settings. Handle first-launch detection (no config → show settings).

**Commit**
`git add . && git commit -m "feat: implement main TabView with monitor and settings tabs"`

---

## Phase 8: Auto-Refresh & Lifecycle

### Task 18: Refresh Manager

**Files:**
- Create: `TokenPlanUsage/Services/RefreshManager.swift`

- Timer-based periodic refresh based on user's interval setting
- `NotificationCenter` observer for `didBecomeActive` → refresh
- Countdown timer for display
- Debounce: don't refresh if last refresh < 60 seconds ago

**Commit**
`git add . && git commit -m "feat: implement auto-refresh manager with lifecycle awareness"`

---

## Phase 9: Widget

### Task 10: Widget Target & Shared Models

**Files:**
- Create: `TokenPlanUsageWidget` target (Widget Extension)
- Share: Models via `#if canImport` or shared framework

Widget reads UsageSnapshot from App Group UserDefaults.

**Commit**
`git add . && git commit -m "feat: scaffold widget target with shared data reading"`

---

### Task 20: Widget Views

**Files:**
- Create: `TokenPlanUsageWidget/SmallWidgetView.swift`
- Create: `TokenPlanUsageWidget/MediumWidgetView.swift`

Small: Provider name + percent + mini ring.
Medium: Add used/total + remaining time.

**Commit**
`git add . && git commit -m "feat: implement small and medium widget views"`

---

### Task 21: Widget Timeline Provider

**Files:**
- Create: `TokenPlanUsageWidget/TokenPlanTimelineProvider.swift`

Read from App Group, provide timeline entries. Reload policy based on refresh interval.

**Commit**
`git add . && git commit -m "feat: implement widget timeline provider"`

---

## Phase 10: Polish & Edge Cases

### Task 22: Error States & Empty States

**Files:**
- Modify: `TokenPlanUsage/Views/Monitor/MonitorView.swift`

Add:
- Skeleton loading view
- "No provider configured" empty state
- Network error overlay
- Stale data warning (> 30 min yellow, > 24 hour red)

**Commit**
`git add . && git commit -m "feat: add loading skeleton, empty state, and error overlays"`

---

### Task 23: Dark Mode & Accessibility

**Files:**
- Modify: various views

- Verify all colors adapt to light/dark mode
- Add accessibility labels for VoiceOver
- Dynamic type support

**Commit**
`git add . && git commit -m "feat: polish dark mode support and accessibility"`

---

### Task 24: Base URL Validation

**Files:**
- Modify: `TokenPlanUsage/ViewModels/SettingsViewModel.swift`

Validate custom Base URL: must start with `https://`, must be valid URL format.

**Commit**
`git add . && git commit -m "feat: add base URL validation in settings"`

---

## Summary

| Phase | Tasks | Est. Time |
|-------|-------|-----------|
| 1. Scaffold & Models | 2 tasks | 1 hour |
| 2. API Layer | 3 tasks | 2-3 hours |
| 3. Storage | 2 tasks | 1 hour |
| 4. View Models | 2 tasks | 1-2 hours |
| 5. Monitor UI | 5 tasks | 3-4 hours |
| 6. Settings UI | 2 tasks | 1-2 hours |
| 7. App Shell | 1 task | 30 min |
| 8. Auto-Refresh | 1 task | 1 hour |
| 9. Widget | 3 tasks | 2-3 hours |
| 10. Polish | 3 tasks | 2 hours |
| **Total** | **24 tasks** | **~15-20 hours** |

---

## Open Items (confirm during development)

1. **MiniMax usage API endpoint** — Need to check platform.minimaxi.com docs or reverse-engineer from the Mac app
2. **GLM balance API endpoint** — Need to check bigmodel.cn dev API docs for balance/usage query
3. **App Group ID** — Set to `group.com.tokenplan.usage`, will need to match provisioning profile
4. **Bundle ID** — TBD, e.g. `com.yourname.TokenPlanUsage`
