import SwiftUI

struct MonitorView: View {
    @State private var selectedProviderIndex = 0

    private let allProviders: [(name: String, provider: TokenProvider, config: ProviderConfig)] = {
        let minimaxProvider = MiniMaxProvider()
        let glmProvider = GLMProvider()
        let deepseekProvider = DeepSeekProvider()
        let minimaxConfig = KeychainService.shared.load(providerId: "minimax") ?? ProviderConfig.minimax
        let glmConfig = KeychainService.shared.load(providerId: "glm") ?? ProviderConfig.glm
        let deepseekConfig = KeychainService.shared.load(providerId: "deepseek") ?? ProviderConfig.deepseek
        return [
            ("MiniMax", minimaxProvider, minimaxConfig),
            ("GLM", glmProvider, glmConfig),
            ("DeepSeek", deepseekProvider, deepseekConfig)
        ]
    }()

    private var providers: [(name: String, provider: TokenProvider, config: ProviderConfig)] {
        // Reads the observable property so SwiftUI re-renders when the
        // Settings tab toggles a provider's `isEnabled` switch.
        let visibleIds = SharedStore.shared.visibleProviderIds
        return allProviders.filter { visibleIds.contains($0.provider.id) }
    }

    var body: some View {
        // Guard against index out-of-bounds when providers are filtered out
        // (e.g. GLM disabled in Settings). Use a clamped index.
        let safeIndex = providers.isEmpty ? 0 : min(selectedProviderIndex, providers.count - 1)
        Group {
            if providers.isEmpty {
                noProvidersState
            } else {
                let current = providers[safeIndex]
                MonitorProviderView(provider: current.provider, config: current.config)
                    .id(safeIndex)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            ProviderSegmentControl(
                                providers: providers.map { $0.name },
                                selectedIndex: safeIndex,
                                onSelect: { index in
                                    selectedProviderIndex = index
                                }
                            )
                        }
                    }
                    .onChange(of: providers.count) { _, _ in
                        // Keep the selected index valid if a provider disappears.
                        if selectedProviderIndex >= providers.count {
                            selectedProviderIndex = max(0, providers.count - 1)
                        }
                    }
            }
        }
    }

    private var noProvidersState: some View {
        VStack(spacing: 12) {
            Image(systemName: "gearshape")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("未启用任何 Provider")
                .font(.headline)
            Text("请前往设置页面启用至少一个 Provider")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

// MARK: - Per-Provider Monitor View

private struct MonitorProviderView: View {
    @State private var viewModel: MonitorViewModel
    private let isGLM: Bool
    private let isDeepSeek: Bool
    private let isMiniMax: Bool

    init(provider: TokenProvider, config: ProviderConfig) {
        _viewModel = State(wrappedValue: MonitorViewModel(provider: provider, config: config))
        self.isGLM = provider.id == "glm"
        self.isDeepSeek = provider.id == "deepseek"
        self.isMiniMax = provider.id == "minimax"
    }

    var body: some View {
        if isDeepSeek {
            deepSeekContent
        } else {
            otherProviderContent
        }
    }

    // MARK: - DeepSeek Content

    private var deepSeekContent: some View {
        Group {
            if let usage = viewModel.platformUsage {
                VStack(spacing: 0) {
                    DeepSeekUsageView(
                        usage: usage,
                        balance: viewModel.snapshot?.balance,
                        isLoading: viewModel.isPlatformUsageLoading,
                        errorMessage: viewModel.platformUsageErrorMessage,
                        onRefresh: { Task { await viewModel.refresh() } },
                        onMonthChange: { month, year in
                            viewModel.onPlatformMonthChanged(month: month, year: year)
                        }
                    )

                    StatusBarView(
                        status: viewModel.platformUsageErrorMessage != nil ? .error(viewModel.platformUsageErrorMessage ?? "") : (viewModel.snapshot?.status ?? .normal),
                        lastUpdated: viewModel.snapshot?.fetchedAt,
                        isLoading: viewModel.isLoading || viewModel.isPlatformUsageLoading,
                        onRefresh: { Task { await viewModel.refresh() } }
                    )
                    .padding()
                }
            } else if viewModel.isPlatformUsageLoading || viewModel.isLoading {
                loadingSkeleton
            } else if let error = viewModel.platformUsageErrorMessage {
                VStack(spacing: 16) {
                    errorOverlay
                    StatusBarView(
                        status: .error(error),
                        lastUpdated: nil,
                        isLoading: false,
                        onRefresh: { Task { await viewModel.refresh() } }
                    )
                }
                .padding()
            } else if viewModel.errorMessage != nil {
                VStack(spacing: 16) {
                    errorOverlay
                    StatusBarView(
                        status: .error(viewModel.errorMessage ?? ""),
                        lastUpdated: nil,
                        isLoading: false,
                        onRefresh: { Task { await viewModel.refresh() } }
                    )
                }
                .padding()
            } else {
                noProviderState
            }
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

    // MARK: - Other Provider Content

    private var otherProviderContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    if let snapshot = viewModel.snapshot {
                        staleDataWarning(snapshot: snapshot)

                        RingProgressView(
                            progress: snapshot.remainingPercent,
                            usedCount: snapshot.usedCount,
                            totalCount: snapshot.totalCount,
                            planName: snapshot.planName,
                            remainingTimeString: formatRemainingTime(snapshot.refreshTime),
                            onRefresh: { Task { await viewModel.refresh() } }
                        )
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))

                        UsageDetailView(
                            usedCount: snapshot.usedCount,
                            totalCount: snapshot.totalCount,
                            remainingPercent: snapshot.remainingPercent,
                            remainingTimeString: formatRemainingTime(snapshot.refreshTime)
                        )

                        if let mcpQuota = snapshot.mcpQuota {
                            MCPQuotaView(quota: mcpQuota)
                        }

                        if let modelQuotas = snapshot.modelQuotas {
                            MiniMaxModelsView(quotas: modelQuotas)
                        }

                        // MiniMax API has no historical time-series data, so the trend
                        // chart is hidden for it (see docs/plans). GLM/others keep it.
                        if !isMiniMax, let distribution = viewModel.distribution {
                            distributionChart(distribution)
                        }
                    } else if viewModel.errorMessage != nil {
                        errorOverlay
                    } else if !viewModel.isLoading {
                        noProviderState
                    } else {
                        loadingSkeleton
                    }
                }
                .padding()
            }

            // StatusBar fixed at the bottom, outside the scroll view (matches DeepSeek layout).
            StatusBarView(
                status: viewModel.errorMessage != nil ? .error(viewModel.errorMessage ?? "") : (viewModel.snapshot?.status ?? .normal),
                lastUpdated: viewModel.snapshot?.fetchedAt,
                isLoading: viewModel.isLoading,
                onRefresh: { Task { await viewModel.refresh() } }
            )
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
        if age > 30 * 60 {
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
            Text(viewModel.errorMessage ?? viewModel.platformUsageErrorMessage ?? "未知错误")
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
        .padding()
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
            Text("请前往设置页面配置 API Key 和 Platform Token")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Distribution Chart

    @ViewBuilder
    private func distributionChart(_ distribution: UsageDistribution) -> some View {
        UsageTrendChart(
            points: distribution.points,
            selectedTimeRange: viewModel.selectedTimeRange,
            totalTokens: distribution.totalTokens,
            isLoading: viewModel.isDistributionLoading,
            errorMessage: viewModel.distributionErrorMessage,
            onTimeRangeChange: { range in
                viewModel.selectedTimeRange = range
                Task { await viewModel.refreshDistribution() }
            },
            onRetry: {
                Task { await viewModel.refreshDistribution() }
            }
        )
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
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
