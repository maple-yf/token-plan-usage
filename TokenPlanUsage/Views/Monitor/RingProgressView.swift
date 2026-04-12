import SwiftUI

struct RingProgressView: View {
    let progress: Double  // 0.0 to 1.0, remaining percent
    let usedCount: Int
    let totalCount: Int
    let planName: String
    let remainingTimeString: String?
    var onRefresh: (() -> Void)?

    @State private var animatedProgress: Double = 0

    private var isPercentageMode: Bool { totalCount == 0 }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(lineWidth: 18)
                    .foregroundStyle(.quaternary)

                // Progress ring
                Circle()
                    .trim(from: 0, to: animatedProgress)
                    .stroke(
                        AngularGradient(
                            colors: [ringColor.opacity(0.8), ringColor],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(duration: 1.0, bounce: 0.4), value: animatedProgress)

                // Center content
                VStack(spacing: 4) {
                    Text(remainingPercentText)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("剩余")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 180, height: 180)
            .contentShape(Circle())
            .onTapGesture {
                onRefresh?()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("用量进度 \(Int(progress * 100))% 剩余")
            .accessibilityHint("点击刷新数据")

            VStack(spacing: 4) {
                Text(planName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(countOrPercentageText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let timeStr = remainingTimeString {
                    Text(timeStr + " 后刷新")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("剩余 \(timeStr) 后刷新")
                }
            }
        }
        .padding()
        .onAppear {
            animatedProgress = progress
        }
        .onChange(of: progress) { _, newValue in
            animatedProgress = newValue
        }
    }

    private var ringColor: Color {
        if progress > 0.5 { return .green }
        if progress > 0.2 { return .orange }
        return .red
    }

    private var remainingPercentText: String {
        String(format: "%.0f%%", progress * 100)
    }

    private var countOrPercentageText: String {
        if isPercentageMode {
            let usedPercent = Int(round((1.0 - progress) * 100))
            return "已用 \(usedPercent)%"
        }
        return "\(usedCount) / \(totalCount) 次"
    }
}

#Preview("Light") {
    ZStack {
        Color.blue.opacity(0.3).ignoresSafeArea()
        RingProgressView(
            progress: 0.958,
            usedCount: 25,
            totalCount: 600,
            planName: "MiniMax-M2.7",
            remainingTimeString: "54:06"
        )
    }
}

#Preview("Dark") {
    ZStack {
        Color.blue.opacity(0.3).ignoresSafeArea()
        RingProgressView(
            progress: 0.958,
            usedCount: 25,
            totalCount: 600,
            planName: "MiniMax-M2.7",
            remainingTimeString: "54:06"
        )
    }
    .preferredColorScheme(.dark)
}
