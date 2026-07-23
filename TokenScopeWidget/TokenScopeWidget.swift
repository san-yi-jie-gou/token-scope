import SwiftUI
import WidgetKit

private enum TokenScopeWidgetStyle {
    static let accent = Color(red: 0.15, green: 0.68, blue: 0.58)
}

struct TokenScopeWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetUsageSnapshot
}

struct TokenScopeTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TokenScopeWidgetEntry {
        TokenScopeWidgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TokenScopeWidgetEntry) -> Void) {
        WidgetSnapshotClient.load { snapshot in
            completion(TokenScopeWidgetEntry(date: Date(), snapshot: snapshot))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TokenScopeWidgetEntry>) -> Void) {
        let now = Date()
        WidgetSnapshotClient.load { snapshot in
            let entry = TokenScopeWidgetEntry(date: now, snapshot: snapshot)
            let nextRefresh = Calendar.current.date(byAdding: .minute, value: 5, to: now) ?? now.addingTimeInterval(300)
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }
}

struct TokenScopeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TokenScopeWidgetEntry

    private let visibleAgentLimit = 4

    private var isStale: Bool {
        entry.snapshot.isStale(relativeTo: entry.date)
    }

    private var hiddenAgentCount: Int {
        max(0, entry.snapshot.agents.count - visibleAgentLimit)
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallView
            default:
                mediumView
            }
        }
        .containerBackground(for: .widget) {
            Color(nsColor: .windowBackgroundColor)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis")
                .foregroundStyle(TokenScopeWidgetStyle.accent)
            Text("TokenScope")
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 4)
            if isStale {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("数据可能已过期")
            }
            Text(entry.snapshot.range.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            VStack(alignment: .leading, spacing: 0) {
                Text(WidgetTokenFormatter.compact(entry.snapshot.displayedTokens))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                Text(entry.snapshot.includesCache ? "tokens · 含缓存" : "tokens · 不含缓存")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                compactMetric("输入", value: entry.snapshot.inputTokens)
                compactMetric("输出", value: entry.snapshot.outputTokens)
            }

            HStack {
                Label("\(entry.snapshot.agents.count)", systemImage: "cpu")
                Spacer()
                Text(entry.snapshot.generatedAt, style: .time)
                if isStale {
                    Text("· 旧数据")
                        .foregroundStyle(.orange)
                }
            }
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
        }
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                header

                VStack(alignment: .leading, spacing: 0) {
                    Text(WidgetTokenFormatter.compact(entry.snapshot.displayedTokens))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                    Text(
                        entry.snapshot.includesCache
                            ? "tokens · 含缓存 · \(entry.snapshot.callCount) 次调用"
                            : "tokens · 不含缓存 · \(entry.snapshot.callCount) 次调用"
                    )
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    compactMetric("输入", value: entry.snapshot.inputTokens)
                    compactMetric("输出", value: entry.snapshot.outputTokens)
                    compactMetric("缓存", value: entry.snapshot.cacheTokens)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(spacing: 8) {
                if entry.snapshot.agents.isEmpty {
                    ContentUnavailableView {
                        Label("暂无记录", systemImage: "clock")
                    }
                } else {
                    ForEach(entry.snapshot.agents.prefix(visibleAgentLimit)) { agent in
                        WidgetAgentRow(agent: agent, total: entry.snapshot.displayedTokens)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        if hiddenAgentCount > 0 {
                            Text("+\(hiddenAgentCount) 其他")
                        }
                        Spacer()
                        Text(entry.snapshot.alternateRangeTitle)
                        Text(WidgetTokenFormatter.compact(entry.snapshot.alternateTokens))
                            .monospacedDigit()
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func compactMetric(_ title: String, value: Int64) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .foregroundStyle(.tertiary)
            Text(WidgetTokenFormatter.compact(value))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 9))
    }
}

private struct WidgetAgentRow: View {
    let agent: WidgetAgentUsage
    let total: Int64

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Circle()
                    .fill(agent.tint)
                    .frame(width: 6, height: 6)
                Text(agent.name)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(WidgetTokenFormatter.compact(agent.tokens))
                    .monospacedDigit()
            }
            .font(.system(size: 10, weight: .medium))

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(agent.tint.opacity(0.8))
                        .frame(width: barWidth(proxy.size.width))
                }
            }
            .frame(height: 4)
        }
    }

    private func barWidth(_ available: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        return max(3, available * CGFloat(Double(agent.tokens) / Double(total)))
    }
}

private enum WidgetTokenFormatter {
    static func compact(_ value: Int64) -> String {
        let amount = Double(value)
        switch amount {
        case 1_000_000_000...:
            return formatted(amount / 1_000_000_000, suffix: "B")
        case 1_000_000...:
            return formatted(amount / 1_000_000, suffix: "M")
        case 1_000...:
            return formatted(amount / 1_000, suffix: "K")
        default:
            return String(value)
        }
    }

    private static func formatted(_ value: Double, suffix: String) -> String {
        let digits = value >= 100 ? 0 : value >= 10 ? 1 : 2
        return value.formatted(.number.precision(.fractionLength(0...digits))) + suffix
    }
}

private extension WidgetUsageSnapshot {
    static let placeholder = WidgetUsageSnapshot(
        generatedAt: Date(),
        range: .today,
        includesCache: false,
        todayTokens: 506_000,
        monthTokens: 6_800_000,
        actualTodayTokens: 506_000,
        selectedTokens: 506_000,
        inputTokens: 420_000,
        outputTokens: 86_000,
        cacheTokens: 774_000,
        callCount: 32,
        agents: [
            WidgetAgentUsage(id: "codex", name: "Codex", tokens: 280_000),
            WidgetAgentUsage(id: "claude", name: "Claude", tokens: 140_000),
            WidgetAgentUsage(id: "kimi", name: "Kimi", tokens: 86_000)
        ]
    )
}

private extension WidgetAgentUsage {
    var tint: Color {
        switch id {
        case "codex": return Color(red: 0.19, green: 0.67, blue: 0.45)
        case "claude": return Color(red: 0.88, green: 0.38, blue: 0.27)
        case "kimi": return Color(red: 0.12, green: 0.58, blue: 0.78)
        case "omp": return Color(red: 0.82, green: 0.60, blue: 0.12)
        case "opencode": return Color(red: 0.66, green: 0.36, blue: 0.72)
        case "gemini": return Color(red: 0.25, green: 0.48, blue: 0.92)
        default: return .secondary
        }
    }
}

struct TokenScopeSystemWidget: Widget {
    let kind = WidgetBridge.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TokenScopeTimelineProvider()) { entry in
            TokenScopeWidgetView(entry: entry)
        }
        .configurationDisplayName("TokenScope")
        .description("查看本地 Coding Agent 的 Token 消耗。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct TokenScopeWidgetBundle: WidgetBundle {
    var body: some Widget {
        TokenScopeSystemWidget()
    }
}
