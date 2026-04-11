import XCTest
@testable import TokenPlanUsage

final class KeychainServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clean up any existing keys
        try? KeychainService.shared.delete(providerId: "test-provider")
    }

    override func tearDown() {
        // Clean up
        try? KeychainService.shared.delete(providerId: "test-provider")
        super.tearDown()
    }

    func testSaveAndLoadProviderConfig() throws {
        let config = ProviderConfig(id: "test-provider", apiKey: "sk-test123", baseURL: nil, isEnabled: true)
        try KeychainService.shared.save(config)

        let loaded = KeychainService.shared.load(providerId: "test-provider")
        XCTAssertNotNil(loaded, "Loaded config should not be nil")
        XCTAssertEqual(loaded?.id, "test-provider")
        XCTAssertEqual(loaded?.apiKey, "sk-test123")
        XCTAssertTrue(loaded?.isEnabled ?? false)
        XCTAssertEqual(loaded?.baseURL, nil)
    }

    func testSaveAndLoadWithBaseURL() throws {
        let config = ProviderConfig(
            id: "test-provider-2",
            apiKey: "sk-another",
            baseURL: "https://custom.api.com",
            isEnabled: false
        )
        try KeychainService.shared.save(config)

        let loaded = KeychainService.shared.load(providerId: "test-provider-2")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.apiKey, "sk-another")
        XCTAssertEqual(loaded?.baseURL, "https://custom.api.com")
        XCTAssertFalse(loaded?.isEnabled ?? true)
    }

    func testLoadNonExistentKeyReturnsNil() {
        let loaded = KeychainService.shared.load(providerId: "non-existent")
        XCTAssertNil(loaded, "Loading non-existent key should return nil")
    }

    func testDeleteKeychainItem() throws {
        let config = ProviderConfig(id: "test-delete", apiKey: "sk-delete", baseURL: nil, isEnabled: true)
        try KeychainService.shared.save(config)
        XCTAssertNotNil(KeychainService.shared.load(providerId: "test-delete"))

        try KeychainService.shared.delete(providerId: "test-delete")
        XCTAssertNil(KeychainService.shared.load(providerId: "test-delete"))
    }

    func testKeychainServiceIsSingleton() {
        let instance1 = KeychainService.shared
        let instance2 = KeychainService.shared
        XCTAssertTrue(instance1 === instance2, "Should be singleton")
    }
}
