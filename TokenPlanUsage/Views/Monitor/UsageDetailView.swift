import SwiftUI

struct UsageDetailView: View {
    let usedCount: Int
    let totalCount: Int
    let remainingTimeString: String?

    private var remainingCount: Int { totalCount - usedCount }

    var body: some View {
        HStack(spacing: 0) {
            detailItem(
                title: "已用次数",
                value: "\(usedCount)",
                icon: "arrow.up.circle.fill",
                color: .blue
            )

            Divider()
                .frame(height: 40)
                .background(.white.opacity(0.2))

            detailItem(
                title: "剩余次数",
                value: "\(remainingCount)",
                icon: "arrow.down.circle.fill",
                color: .green
            )

            Divider()
                .frame(height: 40)
                .background(.white.opacity(0.2))

            detailItem(
                title: "剩余时间",
                value: remainingTimeString ?? "--:--",
                icon: "clock.fill",
                color: .orange
            )
        }
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func detailItem(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    UsageDetailView(
        usedCount: 25,
        totalCount: 600,
        remainingTimeString: "54:06"
    )
    .padding()
    .background(.blue.opacity(0.3))
}
