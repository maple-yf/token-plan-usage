import Foundation

class SharedStore {
    static let shared = SharedStore()

    private let sharedDefaults = UserDefaults(suiteName: "group.com.tokenplan.usage")!
    private let snapshotKey = "UsageSnapshot"
    private let distributionKey = "UsageDistribution"

    func save(snapshot: UsageSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            sharedDefaults.set(data, forKey: snapshotKey)
            sharedDefaults.synchronize()
        }
    }

    func loadSnapshot() -> UsageSnapshot? {
        guard let data = sharedDefaults.data(forKey: snapshotKey) else {
            return nil
        }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    func clearSnapshot() {
        sharedDefaults.removeObject(forKey: snapshotKey)
        sharedDefaults.synchronize()
    }

    func save(distribution: UsageDistribution) {
        if let data = try? JSONEncoder().encode(distribution) {
            sharedDefaults.set(data, forKey: distributionKey)
            sharedDefaults.synchronize()
        }
    }

    func loadDistribution() -> UsageDistribution? {
        guard let data = sharedDefaults.data(forKey: distributionKey) else {
            return nil
        }
        return try? JSONDecoder().decode(UsageDistribution.self, from: data)
    }

    func clearDistribution() {
        sharedDefaults.removeObject(forKey: distributionKey)
        sharedDefaults.synchronize()
    }
}
