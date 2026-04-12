import SwiftUI

struct MCPQuotaView: View {
    let quota: MCPQuota

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label("MCP 工具用量", systemImage: "wrench.and.screwdriver.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(quota.remainingCount) / \(quota.totalCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Progress bar
            ProgressView(value: Double(quota.remainingCount), total: Double(quota.totalCount))
                .tint(quota.remainingCount > quota.totalCount / 2 ? .green : .orange)
                .progressViewStyle(.linear)

            HStack(spacing: 0) {
                mcpStat(title: "已用", value: "\(quota.usedCount)", color: .blue)
                Divider().frame(height: 30).background(.quaternary)
                mcpStat(title: "剩余", value: "\(quota.remainingCount)", color: .green)
                Divider().frame(height: 30).background(.quaternary)
                mcpStat(title: "总量", value: "\(quota.totalCount)", color: .secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("MCP 工具用量：已用 \(quota.usedCount)，剩余 \(quota.remainingCount)，总量 \(quota.totalCount)")
    }

    private func mcpStat(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
