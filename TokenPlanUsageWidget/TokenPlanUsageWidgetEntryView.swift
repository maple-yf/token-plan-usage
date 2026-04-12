import SwiftUI
import WidgetKit

struct TokenPlanUsageWidgetEntryView: View {
    let entry: TokenUsageEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            switch widgetFamily {
            case .systemSmall:
                SmallWidgetView(snapshot: snapshot)
            case .systemMedium:
                MediumWidgetView(snapshot: snapshot)
            default:
                SmallWidgetView(snapshot: snapshot)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "circle.dashed")
                    .font(.title2)
                Text("暂无数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @Environment(\.widgetFamily) var widgetFamily
}

// MARK: - Small Widget

struct SmallWidgetView: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(spacing: 8) {
            Text(snapshot.planName)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 6)

                Circle()
                    .trim(from: 0, to: snapshot.remainingPercent)
                    .stroke(colorForProgress(snapshot.remainingPercent), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text(String(format: "%.0f%%", snapshot.remainingPercent * 100))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .frame(width: 60, height: 60)

            Text("\(snapshot.usedCount)/\(snapshot.totalCount)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

// MARK: - Medium Widget

struct MediumWidgetView: View {
    let snapshot: UsageSnapshot

    var body: some View {
        HStack(spacing: 16) {
            // Left: ring
            SmallWidgetView(snapshot: snapshot)

            // Right: details
            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.planName)
                    .font(.headline)
                    .lineLimit(1)

                HStack {
                    Label("\(snapshot.usedCount) 已用", systemImage: "arrow.up.circle.fill")
                        .font(.caption)
                    Spacer()
                    Label("\(snapshot.totalCount - snapshot.usedCount) 剩余", systemImage: "arrow.down.circle.fill")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

                if let refreshTime = snapshot.refreshTime {
                    let remaining = refreshTime.timeIntervalSinceNow
                    if remaining > 0 {
                        Text("刷新倒计时: \(formatInterval(remaining))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Helpers

private func colorForProgress(_ percent: Double) -> Color {
    if percent > 0.5 { return .green }
    if percent > 0.2 { return .orange }
    return .red
}

private func formatInterval(_ interval: TimeInterval) -> String {
    let hours = Int(interval) / 3600
    let minutes = Int(interval) % 3600 / 60
    if hours > 0 {
        return String(format: "%dh %dm", hours, minutes)
    }
    return String(format: "%dm", minutes)
}
