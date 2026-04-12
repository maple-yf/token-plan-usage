import SwiftUI

struct MonitorView: View {
    @State private var viewModel: MonitorViewModel

    init(provider: TokenProvider, config: ProviderConfig) {
        _viewModel = State(wrappedValue: MonitorViewModel(provider: provider, config: config))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Provider segment control
                ProviderSegmentControl(
                    providers: ["MiniMax", "GLM"],
                    selectedIndex: 0
                )

                if let snapshot = viewModel.snapshot {
                    // Ring progress
                    RingProgressView(
                        progress: snapshot.remainingPercent,
                        usedCount: snapshot.usedCount,
                        totalCount: snapshot.totalCount,
                        planName: snapshot.planName,
                        remainingTimeString: formatRemainingTime(snapshot.refreshTime)
                    )
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))

                    // Usage detail
                    UsageDetailView(
                        usedCount: snapshot.usedCount,
                        totalCount: snapshot.totalCount,
                        remainingTimeString: formatRemainingTime(snapshot.refreshTime)
                    )

                    // Trend chart
                    if let distribution = viewModel.distribution {
                        UsageTrendChart(points: distribution.points)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                } else if viewModel.errorMessage != nil {
                    errorOverlay
                } else {
                    emptyState
                }

                // Status bar
                StatusBarView(
                    status: viewModel.snapshot?.status ?? .normal,
                    lastUpdated: viewModel.snapshot?.fetchedAt,
                    isLoading: viewModel.isLoading,
                    onRefresh: { Task { await viewModel.refresh() } }
                )
            }
            .padding()
        }
        .background(
            LinearGradient(
                colors: [.blue.opacity(0.3), .purple.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .task {
            await viewModel.refresh()
        }
    }

    private var errorOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(viewModel.errorMessage ?? "未知错误")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("重试") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.5)
            Text("正在获取用量数据…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func formatRemainingTime(_ date: Date?) -> String? {
        guard let date = date else { return nil }
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return nil }
        let hours = Int(interval) / 3600
        let minutes = Int(interval) % 3600 / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Provider Segment Control

struct ProviderSegmentControl: View {
    let providers: [String]
    let selectedIndex: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(providers.enumerated()), id: \.offset) { index, name in
                Button {} label: {
                    Text(name)
                        .font(.subheadline.weight(selectedIndex == index ? .semibold : .regular))
                        .foregroundStyle(selectedIndex == index ? .primary : .secondary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(
                            selectedIndex == index
                                ? AnyShapeStyle(.ultraThinMaterial)
                                : AnyShapeStyle(.clear)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview("Monitor") {
    MonitorView(
        provider: PreviewTokenProvider(),
        config: ProviderConfig(id: "minimax", apiKey: "test", baseURL: nil, isEnabled: true)
    )
}

private struct PreviewTokenProvider: TokenProvider {
    let id = "minimax"
    let displayName = "MiniMax"
    let defaultBaseURL = "https://api.minimax.chat"
    func fetchUsage(apiKey: String, baseURL: String?) async throws -> UsageSnapshot {
        UsageSnapshot(providerId: "minimax", planName: "MiniMax-M2.7",
            usedCount: 25, totalCount: 600, remainingPercent: 0.958,
            refreshTime: Date().addingTimeInterval(3246), fetchedAt: Date(), status: .normal)
    }
    func fetchDistribution(apiKey: String, baseURL: String?) async throws -> UsageDistribution {
        UsageDistribution(providerId: "minimax",
            windowStart: Date().addingTimeInterval(-3600), windowEnd: Date(), points: [])
    }
}
