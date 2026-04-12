import SwiftUI

struct MonitorView: View {
    @State private var selectedProviderIndex = 0

    private let providers: [(name: String, provider: TokenProvider, config: ProviderConfig)] = {
        let minimaxProvider = MiniMaxProvider()
        let glmProvider = GLMProvider()
        let minimaxConfig = KeychainService.shared.load(providerId: "minimax") ?? ProviderConfig.minimax
        let glmConfig = KeychainService.shared.load(providerId: "glm") ?? ProviderConfig.glm
        return [
            ("MiniMax", minimaxProvider, minimaxConfig),
            ("GLM", glmProvider, glmConfig)
        ]
    }()

    var body: some View {
        let current = providers[selectedProviderIndex]
        MonitorProviderView(provider: current.provider, config: current.config)
            .id(selectedProviderIndex)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ProviderSegmentControl(
                        providers: providers.map { $0.name },
                        selectedIndex: selectedProviderIndex,
                        onSelect: { index in
                            selectedProviderIndex = index
                        }
                    )
                }
            }
    }
}

// MARK: - Per-Provider Monitor View

private struct MonitorProviderView: View {
    @State private var viewModel: MonitorViewModel

    init(provider: TokenProvider, config: ProviderConfig) {
        _viewModel = State(wrappedValue: MonitorViewModel(provider: provider, config: config))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let snapshot = viewModel.snapshot {
                    // Stale data warning
                    staleDataWarning(snapshot: snapshot)

                    // Ring progress
                    RingProgressView(
                        progress: snapshot.remainingPercent,
                        usedCount: snapshot.usedCount,
                        totalCount: snapshot.totalCount,
                        planName: snapshot.planName,
                        remainingTimeString: formatRemainingTime(snapshot.refreshTime),
                        onRefresh: { Task { await viewModel.refresh() } }
                    )
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))

                    // Usage detail
                    UsageDetailView(
                        usedCount: snapshot.usedCount,
                        totalCount: snapshot.totalCount,
                        remainingPercent: snapshot.remainingPercent,
                        remainingTimeString: formatRemainingTime(snapshot.refreshTime)
                    )

                    // MCP quota (GLM only)
                    if let mcpQuota = snapshot.mcpQuota {
                        MCPQuotaView(quota: mcpQuota)
                    }

                    // MiniMax model quotas
                    if let modelQuotas = snapshot.modelQuotas {
                        MiniMaxModelsView(quotas: modelQuotas)
                    }

                    // Trend chart (skip for MiniMax — no historical data)
                    if let distribution = viewModel.distribution, !distribution.points.isEmpty {
                        UsageTrendChart(points: distribution.points)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                } else if viewModel.errorMessage != nil {
                    errorOverlay
                } else if !viewModel.isLoading {
                    noProviderState
                } else {
                    loadingSkeleton
                }

                // Status bar
                StatusBarView(
                    status: viewModel.errorMessage != nil ? .error(viewModel.errorMessage ?? "") : (viewModel.snapshot?.status ?? .normal),
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

    // MARK: - Stale Data Warning

    @ViewBuilder
    private func staleDataWarning(snapshot: UsageSnapshot) -> some View {
        let age = Date().timeIntervalSince(snapshot.fetchedAt)
        if age > 30 * 60 { // 30 minutes
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(age > 24 * 3600 ? .red : .yellow)
                Text(age > 24 * 3600
                     ? "数据已超过 24 小时未更新"
                     : "数据已超过 30 分钟未更新")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                (age > 24 * 3600 ? Color.red : Color.yellow).opacity(0.15),
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
    }

    // MARK: - Error Overlay

    private var errorOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(viewModel.errorMessage ?? "未知错误")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重试") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Loading Skeleton

    private var loadingSkeleton: some View {
        VStack(spacing: 20) {
            // Skeleton ring
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 18)
                .frame(width: 180, height: 180)
                .overlay {
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 80, height: 28)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.15))
                            .frame(width: 40, height: 14)
                    }
                }

            // Skeleton details
            HStack(spacing: 0) {
                skeletonDetailItem
                skeletonDetailItem
                skeletonDetailItem
            }
            .padding(.vertical, 16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

            ProgressView()
                .padding(.top, 8)
        }
    }

    private var skeletonDetailItem: some View {
        VStack(spacing: 6) {
            Circle()
                .fill(Color.gray.opacity(0.15))
                .frame(width: 20, height: 20)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 50, height: 20)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.15))
                .frame(width: 36, height: 12)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - No Provider State

    private var noProviderState: some View {
        VStack(spacing: 12) {
            Image(systemName: "gearshape")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("未配置 Provider")
                .font(.headline)
            Text("请前往设置页面配置 API Key")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Helpers

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
    var onSelect: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(providers.enumerated()), id: \.offset) { index, name in
                Button {
                    onSelect?(index)
                } label: {
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
    MonitorView()
}
