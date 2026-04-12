import UIKit

@Observable
class RefreshManager {
    var countdown: TimeInterval = 0
    var isRefreshing = false

    private var timer: Timer?
    private var lastRefreshTime: Date = .distantPast
    private let minimumInterval: TimeInterval = 60 // debounce: 60 seconds

    private var refreshInterval: TimeInterval
    private let onRefresh: () async -> Void

    init(refreshInterval: TimeInterval, onRefresh: @escaping () async -> Void) {
        self.refreshInterval = refreshInterval
        self.onRefresh = onRefresh

        // Listen for app becoming active
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    deinit {
        stopTimer()
        NotificationCenter.default.removeObserver(self)
    }

    func start() {
        guard refreshInterval > 0 else { return } // manual mode
        countdown = refreshInterval
        lastRefreshTime = Date()

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.tick()
        }
    }

    func stop() {
        stopTimer()
    }

    func triggerRefresh() async {
        let now = Date()
        guard now.timeIntervalSince(lastRefreshTime) >= minimumInterval else {
            // Debounce: skip if refreshed less than 60 seconds ago
            return
        }
        guard !isRefreshing else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        lastRefreshTime = now
        countdown = refreshInterval

        await onRefresh()
    }

    func updateInterval(_ newInterval: TimeInterval) {
        stopTimer()
        refreshInterval = newInterval
        guard newInterval > 0 else { return }
        start()
    }

    @objc private func appDidBecomeActive() {
        Task {
            await triggerRefresh()
        }
    }

    private func tick() {
        guard refreshInterval > 0 else { return }
        countdown -= 1
        if countdown <= 0 {
            countdown = refreshInterval
            Task {
                await triggerRefresh()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
