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
        VStack(spacing: 6) {
            HStack {
                Text(quota.modelName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(quota.remainingCount) / \(quota.totalCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(quota.remainingCount), total: Double(max(quota.totalCount, 1)))
                .tint(progressColor(remaining: quota.remainingCount, total: quota.totalCount))
                .progressViewStyle(.linear)

            HStack(spacing: 0) {
                statItem(title: "已用", value: "\(quota.usedCount)", color: .blue)
                Divider().frame(height: 24).background(.quaternary)
                statItem(title: "剩余", value: "\(quota.remainingCount)", color: .green)
                Divider().frame(height: 24).background(.quaternary)
                statItem(title: "总量", value: "\(quota.totalCount)", color: .secondary)
            }
        }
    }

    private func statItem(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func progressColor(remaining: Int, total: Int) -> Color {
        guard total > 0 else { return .gray }
        let ratio = Double(remaining) / Double(total)
        if ratio > 0.5 { return .green }
        if ratio > 0.2 { return .orange }
        return .red
    }
}
