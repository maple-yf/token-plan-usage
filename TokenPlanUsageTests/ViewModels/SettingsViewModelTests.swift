import XCTest
@testable import TokenPlanUsage

final class SettingsViewModelTests: XCTestCase {

    var vm: SettingsViewModel!
    var keychainService: KeychainService!

    override func setUp() {
        super.setUp()
        keychainService = KeychainService.shared
        // Clean up any existing keys
        try? keychainService.delete(providerId: "minimax")
        try? keychainService.delete(providerId: "glm")
        vm = SettingsViewModel()
    }

    override func tearDown() async throws {
        try await super.tearDown()
        try? keychainService.delete(providerId: "minimax")
        try? keychainService.delete(providerId: "glm")
    }

    // MARK: - Initial State

    func testInitialLoadDefaults() {
        XCTAssertNotNil(vm.providers)
        XCTAssertEqual(vm.providers.count, 2)
        XCTAssertEqual(vm.providers[0].id, "minimax")
        XCTAssertEqual(vm.providers[1].id, "glm")
        XCTAssertEqual(vm.refreshInterval, 300)
        XCTAssertEqual(vm.widgetProvider, "minimax")
    }

    // MARK: - Provider Updates

    func testUpdateProvider() throws {
        let newConfig = ProviderConfig(
            id: "minimax",
            apiKey: "sk-new-key",
            baseURL: "https://custom.api.com",
            isEnabled: true
        )

        do {
            try vm.updateProvider(newConfig)
        } catch KeychainService.KeychainError.additionFailed {
            throw XCTSkip("Keychain unavailable in test runner")
        }

        let loaded = keychainService.load(providerId: "minimax")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.apiKey, "sk-new-key")
        XCTAssertEqual(loaded?.baseURL, "https://custom.api.com")
    }

    func testUpdateProviderPersistsAcrossInstances() throws {
        let newConfig = ProviderConfig(
            id: "glm",
            apiKey: "sk-glm-test",
            baseURL: nil,
            isEnabled: true
        )

        do {
            try vm.updateProvider(newConfig)
        } catch KeychainService.KeychainError.additionFailed {
            throw XCTSkip("Keychain unavailable in test runner")
        }

        // Create a new instance to verify persistence
        let vm2 = SettingsViewModel()
        let glmProvider = vm2.providers.first { $0.id == "glm" }
        XCTAssertNotNil(glmProvider)
        XCTAssertEqual(glmProvider?.apiKey, "sk-glm-test")
    }

    func testUpdateProviderRejectsInvalidBaseURL() {
        let config = ProviderConfig(
            id: "minimax",
            apiKey: "sk-test",
            baseURL: "http://insecure.com",
            isEnabled: true
        )

        XCTAssertThrowsError(try vm.updateProvider(config)) { error in
            XCTAssertTrue(error is SettingsViewModel.SettingsError)
        }
    }

    // MARK: - Toggle

    func testToggleProvider() throws {
        XCTAssertTrue(vm.providers[0].isEnabled)
        do {
            try vm.toggleProvider("minimax")
        } catch KeychainService.KeychainError.additionFailed {
            throw XCTSkip("Keychain unavailable in test runner")
        }
        XCTAssertFalse(vm.providers[0].isEnabled)

        let loaded = keychainService.load(providerId: "minimax")
        XCTAssertNotNil(loaded)
        XCTAssertFalse(loaded?.isEnabled ?? true)
    }

    // MARK: - Base URL Validation

    func testValidateBaseURLValid() {
        XCTAssertTrue(vm.validateBaseURL("https://example.com"))
        XCTAssertNil(vm.baseURLValidationError)
        XCTAssertTrue(vm.validateBaseURL(nil))
        XCTAssertTrue(vm.validateBaseURL(""))  // empty = use default = valid
        XCTAssertTrue(vm.validateBaseURL("https://api.minimax.chat/v1"))
        XCTAssertTrue(vm.validateBaseURL("https://open.bigmodel.cn/api/paas/v4"))
    }

    func testValidateBaseURLInvalid() {
        XCTAssertFalse(vm.validateBaseURL("http://insecure.com"))
        XCTAssertNotNil(vm.baseURLValidationError)

        XCTAssertFalse(vm.validateBaseURL("ftp://example.com"))
        XCTAssertFalse(vm.validateBaseURL("not-a-url"))
        XCTAssertFalse(vm.validateBaseURL("https://"))
    }

    func testValidateBaseURLErrorMessage() {
        _ = vm.validateBaseURL("http://test.com")
        XCTAssertEqual(vm.baseURLValidationError, "Base URL 必须以 https:// 开头")

        _ = vm.validateBaseURL("https://")
        XCTAssertEqual(vm.baseURLValidationError, "URL 格式无效")
    }

    // MARK: - Settings

    func testRefreshInterval() {
        vm.refreshInterval = 10 * 60
        XCTAssertEqual(vm.refreshInterval, 600)
    }

    func testWidgetProvider() {
        vm.widgetProvider = "glm"
        XCTAssertEqual(vm.widgetProvider, "glm")
    }
}
