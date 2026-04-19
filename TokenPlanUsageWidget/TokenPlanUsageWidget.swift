import WidgetKit
import SwiftUI

struct TokenUsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
}

// MARK: - Timeline Provider

struct TokenUsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> TokenUsageEntry {
        TokenUsageEntry(
            date: Date(),
            snapshot: UsageSnapshot(
                providerId: "minimax",
                planName: "MiniMax-M2.7",
                usedCount: 25,
                totalCount: 600,
                remainingPercent: 0.958,
                refreshTime: nil,
                fetchedAt: Date(),
                status: .normal,
                mcpQuota: nil,
                modelQuotas: nil
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TokenUsageEntry) -> Void) {
        let snapshot = loadSnapshot()
        completion(TokenUsageEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TokenUsageEntry>) -> Void) {
        let snapshot = loadSnapshot()
        let entry = TokenUsageEntry(date: Date(), snapshot: snapshot)

        // Refresh every 5 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadSnapshot() -> UsageSnapshot? {
        let sharedStore = SharedStore.shared
        let selectedProvider = sharedStore.loadWidgetProvider()
        // Use the user-selected provider, fallback to the most recently fetched
        if let snapshot = sharedStore.loadSnapshot(providerId: selectedProvider) {
            return snapshot
        }
        let providers = ["minimax", "glm"]
        return providers.compactMap { sharedStore.loadSnapshot(providerId: $0) }
            .sorted { $0.fetchedAt > $1.fetchedAt }
            .first
    }
}

// MARK: - Widget

struct TokenPlanUsageWidget: Widget {
    let kind: String = "TokenPlanUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TokenUsageProvider()) { entry in
            TokenPlanUsageWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName("Token Usage")
        .description("显示 API Token 用量和剩余额度")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Widget Bundle

@main
struct TokenPlanUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        TokenPlanUsageWidget()
    }
}
