import SwiftUI

struct MiniMaxModelsView: View {
    let quotas: [MiniMaxModelQuota]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label("模型用量", systemImage: "server.rack")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(quotas.count) 个模型")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(quotas) { quota in
                modelRow(quota: quota)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("模型用量：\(quotas.count) 个模型")
    }

    private func modelRow(quota: MiniMaxModelQuota) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(quota.modelName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                if quota.isWeeklyUnlimited {
                    Text("周额度 无限制")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // 5-hour interval progress (remaining)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("5 小时限额")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "剩余 %.0f%% · 已用 %.0f%%",
                                quota.intervalRemainingPercent,
                                quota.intervalUsedPercent))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: quota.intervalRemainingPercent, total: 100)
                    .tint(progressColor(remainingPercent: quota.intervalRemainingPercent))
                    .progressViewStyle(.linear)
            }

            // Weekly quota (if not unlimited and data present)
            if !quota.isWeeklyUnlimited, let weeklyRemaining = quota.weeklyRemainingPercent {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("周额度")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "剩余 %.0f%% · 已用 %.0f%%",
                                    weeklyRemaining,
                                    max(0, 100 - weeklyRemaining)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: weeklyRemaining, total: 100)
                        .tint(progressColor(remainingPercent: weeklyRemaining))
                        .progressViewStyle(.linear)
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func progressColor(remainingPercent: Double) -> Color {
        if remainingPercent > 50 { return .green }
        if remainingPercent > 20 { return .orange }
        return .red
    }
}

#Preview {
    MiniMaxModelsView(quotas: [
        MiniMaxModelQuota(modelName: "MiniMax-M*", intervalRemainingPercent: 95.8, weeklyStatus: 3, weeklyRemainingPercent: nil),
        MiniMaxModelQuota(modelName: "speech-hd", intervalRemainingPercent: 42, weeklyStatus: 0, weeklyRemainingPercent: 88.5)
    ])
    .background(.blue.opacity(0.3))
}
