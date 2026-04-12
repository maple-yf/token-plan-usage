import SwiftUI

struct StatusBarView: View {
    let status: APIStatus
    let lastUpdated: Date?
    let isLoading: Bool
    let onRefresh: () -> Void

    private var statusColor: Color {
        switch status {
        case .normal: return .green
        case .error: return .red
        }
    }

    private var statusText: String {
        switch status {
        case .normal: return "API 正常"
        case .error(let msg): return "API 异常: \(msg)"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.5), radius: 4)
                .accessibilityHidden(true)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Last updated time
            if let lastUpdated = lastUpdated {
                Text("更新: \(lastUpdated, style: .time)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Refresh button
            Button(action: onRefresh) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 32, height: 32)

                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .disabled(isLoading)
            .accessibilityLabel("刷新数据")
            .accessibilityHint("下拉获取最新用量数据")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("状态栏：\(statusText)，\(lastUpdated != nil ? "最后更新 \(lastUpdated!.formatted(date: .omitted, time: .shortened))" : "尚未更新")")
    }
}

#Preview {
    VStack(spacing: 16) {
        StatusBarView(
            status: .normal,
            lastUpdated: Date(),
            isLoading: false,
            onRefresh: {}
        )
        StatusBarView(
            status: .error("unauthorized"),
            lastUpdated: nil,
            isLoading: true,
            onRefresh: {}
        )
    }
    .padding()
    .background(.blue.opacity(0.3))
}
