import Foundation

class SharedStore {
    static let shared = SharedStore()

    private let sharedDefaults = UserDefaults(suiteName: "group.com.tokenplan.usage")!

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

    func saveWidgetProvider(_ providerId: String) {
        sharedDefaults.set(providerId, forKey: "SelectedWidgetProvider")
        sharedDefaults.synchronize()
    }

    func loadWidgetProvider() -> String {
        sharedDefaults.string(forKey: "SelectedWidgetProvider") ?? "minimax"
    }
}
