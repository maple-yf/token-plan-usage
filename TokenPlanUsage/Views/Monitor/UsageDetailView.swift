import SwiftUI

struct UsageDetailView: View {
    let usedCount: Int
    let totalCount: Int
    let remainingPercent: Double
    let remainingTimeString: String?

    private var isPercentageMode: Bool { totalCount == 0 }
    private var remainingCount: Int { totalCount - usedCount }

    var body: some View {
        HStack(spacing: 0) {
            if isPercentageMode {
                detailItem(
                    title: "已用",
                    value: "\(Int(round((1.0 - remainingPercent) * 100)))%",
                    icon: "arrow.up.circle.fill",
                    color: .blue
                )

                Divider()
                    .frame(height: 40)
                    .background(.quaternary)

                detailItem(
                    title: "剩余",
                    value: "\(Int(round(remainingPercent * 100)))%",
                    icon: "arrow.down.circle.fill",
                    color: .green
                )
            } else {
                detailItem(
                    title: "已用次数",
                    value: "\(usedCount)",
                    icon: "arrow.up.circle.fill",
                    color: .blue
                )

                Divider()
                    .frame(height: 40)
                    .background(.quaternary)

                detailItem(
                    title: "剩余次数",
                    value: "\(remainingCount)",
                    icon: "arrow.down.circle.fill",
                    color: .green
                )
            }

            Divider()
                .frame(height: 40)
                .background(.quaternary)

            detailItem(
                title: "剩余时间",
                value: remainingTimeString ?? "--:--",
                icon: "clock.fill",
                color: .orange
            )
        }
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(percentageModeAccessibility)
    }

    private var percentageModeAccessibility: String {
        let used = Int(round((1.0 - remainingPercent) * 100))
        let remaining = Int(round(remainingPercent * 100))
        return "用量详情：已用 \(used)%，剩余 \(remaining)%，剩余时间 \(remainingTimeString ?? "未知")"
    }

    private func detailItem(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)
                .accessibilityHidden(true)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }
}

#Preview {
    UsageDetailView(
        usedCount: 25,
        totalCount: 600,
        remainingPercent: 0.958,
        remainingTimeString: "54:06"
    )
    .padding()
    .background(.blue.opacity(0.3))
}
