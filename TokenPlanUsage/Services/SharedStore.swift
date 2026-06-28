import Foundation
import Observation

@Observable
final class SharedStore {
    static let shared = SharedStore()

    /// Provider IDs that should appear as tabs in the Monitor view.
    /// Mirrors `ProviderConfig.isEnabled` so changes from the Settings tab
    /// propagate to the Monitor tab without extra plumbing.
    var visibleProviderIds: [String]

    private let sharedDefaults = UserDefaults(suiteName: "group.com.tokenplan.usage")!
    private let visibleProvidersKey = "VisibleProviderIds"

    private init() {
        self.visibleProviderIds = sharedDefaults.stringArray(forKey: "VisibleProviderIds")
            ?? ["minimax", "glm", "deepseek"]
    }

    func save(snapshot: UsageSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            sharedDefaults.set(data, forKey: "UsageSnapshot_\(snapshot.providerId)")
            sharedDefaults.synchronize()
        }
    }

    func loadSnapshot(providerId: String) -> UsageSnapshot? {
        guard let data = sharedDefaults.data(forKey: "UsageSnapshot_\(providerId)") else {
            return nil
        }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    func save(distribution: UsageDistribution) {
        if let data = try? JSONEncoder().encode(distribution) {
            sharedDefaults.set(data, forKey: "UsageDistribution_\(distribution.providerId)")
            sharedDefaults.synchronize()
        }
    }

    func loadDistribution(providerId: String) -> UsageDistribution? {
        guard let data = sharedDefaults.data(forKey: "UsageDistribution_\(providerId)") else {
            return nil
        }
        return try? JSONDecoder().decode(UsageDistribution.self, from: data)
    }

    // MARK: - Visible Providers (for Monitor tab)

    /// Idempotent: setting `visible: false` removes the id (if present);
    /// setting `visible: true` adds the id (if missing). Calling twice
    /// with the same flag leaves the list unchanged.
    func setProviderVisibility(_ providerId: String, visible: Bool) {
        var ids = visibleProviderIds
        let contains = ids.contains(providerId)
        guard contains != visible else { return }
        if visible {
            ids.append(providerId)
        } else {
            ids.removeAll { $0 == providerId }
        }
        visibleProviderIds = ids
        sharedDefaults.set(ids, forKey: visibleProvidersKey)
        sharedDefaults.synchronize()
    }

    func isProviderVisible(_ providerId: String) -> Bool {
        visibleProviderIds.contains(providerId)
    }
}
