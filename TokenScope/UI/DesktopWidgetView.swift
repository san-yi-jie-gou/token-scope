import Charts
import SwiftUI

private enum TokenScopeStyle {
    static let accent = Color(red: 0.15, green: 0.68, blue: 0.58)
    static let cornerRadius: CGFloat = 14
}

struct DesktopWidgetView: View {
    @ObservedObject var store: UsageStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var summary: UsageSummary { store.summary }
    private var displayedTotal: Int64 {
        summary.tokens.total(includingCache: store.includesCache)
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            totalSection
            sourceBar
            if store.range == .month && !store.dailyUsage.isEmpty {
                MonthlyUsageChart(days: store.dailyUsage, includesCache: store.includesCache)
            }
            sourceRows
            footer
        }
        .padding(18)
        .frame(
            width: WidgetLayout.width,
            height: WidgetLayout.height(activeAgentCount: summary.sources.count, range: store.range)
        )
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: TokenScopeStyle.cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: TokenScopeStyle.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.11), lineWidth: 1)
        }
        .contextMenu {
            Button("刷新", systemImage: "arrow.clockwise") { store.refresh() }
            Divider()
            ForEach(UsageRange.allCases) { range in
                Button(range.title) { store.range = range }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TokenScopeStyle.accent)
                .frame(width: 24, height: 24)
                .background(
                    TokenScopeStyle.accent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )

            Text("TokenScope")
                .font(.system(size: 15, weight: .semibold))

            Spacer(minLength: 8)

            Picker("统计周期", selection: $store.range) {
                ForEach(UsageRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 116)

            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(store.isRefreshing && !reduceMotion ? 360 : 0))
                    .animation(
                        store.isRefreshing && !reduceMotion
                            ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                            : nil,
                        value: store.isRefreshing
                    )
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(store.isRefreshing || !store.hasDataDirectoryAccess)
            .help("刷新用量")
            .accessibilityLabel("刷新用量")
        }
    }

    private var totalSection: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("总消耗")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .help(store.includesCache ? "输入、输出与缓存 Token" : "仅输入与输出 Token")
                Text(TokenFormatter.compact(displayedTotal))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(displayedTotal)))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: displayedTotal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Text("tokens")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 5)

            Spacer()

            if displayedTotal > 0 {
                Text("\(summary.eventCount) 次调用")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 5)
            }
        }
    }

    private var sourceBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(summary.sources) { item in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(item.source.tint)
                        .frame(
                            width: segmentWidth(
                                item.tokens.total(includingCache: store.includesCache),
                                total: displayedTotal,
                                width: proxy.size.width
                            )
                        )
                }
            }
        }
        .frame(height: 8)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 2, style: .continuous))
        .clipped()
        .animation(reduceMotion ? nil : .snappy(duration: 0.34), value: summary.sources)
    }

    private var sourceRows: some View {
        Group {
            if !store.hasDataDirectoryAccess {
                Button {
                    store.onRequestDataDirectoryAccess?()
                } label: {
                    Label("授权数据目录", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 22)
            } else if summary.sources.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                    Text(store.range == .today ? "今天还没有 Token 记录" : "本月还没有 Token 记录")
                }
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 22)
            } else {
                VStack(spacing: 9) {
                    ForEach(summary.sources) { item in
                        SourceUsageRow(
                            summary: item,
                            grandTotal: displayedTotal,
                            includesCache: store.includesCache
                        )
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            MetricLabel(title: "输入", value: summary.tokens.input)
            MetricLabel(title: "输出", value: summary.tokens.output)
            MetricLabel(title: "缓存", value: summary.tokens.cacheRead + summary.tokens.cacheWrite)

            Spacer(minLength: 4)

            if let lastUpdated = store.lastUpdated {
                Text(lastUpdated, format: .dateTime.hour().minute())
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            } else if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.top, 2)
    }

    private func segmentWidth(_ value: Int64, total: Int64, width: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        return max(3, width * CGFloat(Double(value) / Double(total)))
    }
}

private struct MonthlyUsageChart: View {
    let days: [DailyUsageSummary]
    let includesCache: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredDate: Date?

    private var peak: Int64 {
        days.map { chartTotal($0.tokens) }.max() ?? 0
    }

    private var hoveredDay: DailyUsageSummary? {
        guard let hoveredDate else { return nil }
        return days.first { Calendar.current.isDate($0.date, inSameDayAs: hoveredDate) }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("每日消耗")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Group {
                    if let hoveredDay {
                        HStack(spacing: 4) {
                            Text(hoveredDay.date, format: .dateTime.month().day())
                            Text("·")
                            Text(TokenFormatter.compact(chartTotal(hoveredDay.tokens)))
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .contentTransition(
                                    .numericText(value: Double(chartTotal(hoveredDay.tokens)))
                                )
                            Text("· \(hoveredDay.eventCount) 次")
                        }
                    } else {
                        Text("峰值 \(TokenFormatter.compact(peak))")
                    }
                }
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .transition(.opacity)
            }

            Chart {
                ForEach(days) { day in
                    ForEach(day.sources.sorted { $0.source.id < $1.source.id }) { source in
                        BarMark(
                            x: .value("日期", day.date, unit: .day),
                            y: .value("Tokens", chartTotal(source.tokens))
                        )
                        .foregroundStyle(source.source.tint)
                        .cornerRadius(2)
                        .opacity(barOpacity(for: day))
                    }
                }

                if let hoveredDay {
                    RuleMark(x: .value("选中日期", hoveredDay.date, unit: .day))
                        .foregroundStyle(Color.primary.opacity(0.28))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                    PointMark(
                        x: .value("选中日期", hoveredDay.date, unit: .day),
                        y: .value("当日 Tokens", chartTotal(hoveredDay.tokens))
                    )
                    .foregroundStyle(Color.primary.opacity(0.72))
                    .symbolSize(24)
                }
            }
            .chartXScale(domain: chartDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { value in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.05))
                    AxisTick().foregroundStyle(Color.primary.opacity(0.18))
                    AxisValueLabel(format: .dateTime.day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 2)) { value in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel {
                        if let tokenCount = value.as(Int64.self) {
                            Text(TokenFormatter.compact(tokenCount))
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                updateHover(at: location, proxy: proxy, geometry: geometry)
                            case .ended:
                                setHoveredDate(nil)
                            }
                        }
                }
            }
            .frame(height: 72)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: includesCache)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hoveredDate)
            .accessibilityLabel("本月每日 Token 消耗")
            .accessibilityValue("峰值 \(TokenFormatter.compact(peak))")
        }
    }

    private func barOpacity(for day: DailyUsageSummary) -> Double {
        guard let hoveredDate else { return 0.9 }
        return Calendar.current.isDate(day.date, inSameDayAs: hoveredDate) ? 1 : 0.26
    }

    private func updateHover(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else {
            setHoveredDate(nil)
            return
        }
        let frame = geometry[plotFrame]
        guard frame.contains(location) else {
            setHoveredDate(nil)
            return
        }
        let plotX = location.x - frame.minX
        guard let date: Date = proxy.value(atX: plotX),
              let nearestDate = nearestUsageDate(to: date) else {
            setHoveredDate(nil)
            return
        }
        setHoveredDate(nearestDate)
    }

    private func nearestUsageDate(to date: Date) -> Date? {
        let nearest = days.map(\.date).min {
            abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date))
        }
        guard let nearest,
              abs(nearest.timeIntervalSince(date)) <= 18 * 60 * 60 else {
            return nil
        }
        return nearest
    }

    private func setHoveredDate(_ date: Date?) {
        guard hoveredDate != date else { return }
        hoveredDate = date
    }

    private func chartTotal(_ tokens: TokenBreakdown) -> Int64 {
        includesCache ? tokens.total : max(0, tokens.input) + max(0, tokens.output)
    }

    private var chartDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        let start = UsageRange.month.startDate(calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
        return start...end
    }
}

private struct SourceUsageRow: View {
    let summary: SourceUsageSummary
    let grandTotal: Int64
    let includesCache: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var displayedTotal: Int64 {
        summary.tokens.total(includingCache: includesCache)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: summary.source.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(summary.source.tint)
                .frame(width: 20, height: 20)
                .background(summary.source.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .scaleEffect(isHovered ? 1.08 : 1)

            Text(summary.source.displayName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 68, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07))
                    Capsule()
                        .fill(summary.source.tint.opacity(isHovered ? 0.96 : 0.78))
                        .frame(width: barWidth(proxy.size.width))
                        .scaleEffect(y: isHovered ? 1.35 : 1)
                }
            }
            .frame(height: 5)

            Text(TokenFormatter.compact(displayedTotal))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(displayedTotal)))
        }
        .font(.system(size: 11))
        .padding(.horizontal, 6)
        .frame(height: 22)
        .background(
            summary.source.tint.opacity(isHovered ? 0.08 : 0),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summary.source.displayName)，\(TokenFormatter.compact(displayedTotal)) tokens")
    }

    private func barWidth(_ available: CGFloat) -> CGFloat {
        guard grandTotal > 0, displayedTotal > 0 else { return 0 }
        return max(3, available * CGFloat(Double(displayedTotal) / Double(grandTotal)))
    }
}

private struct MetricLabel: View {
    let title: String
    let value: Int64

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.tertiary)
            Text(TokenFormatter.compact(value))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 10))
    }
}

private extension UsageSource {
    var tint: Color {
        switch id {
        case UsageSource.codex.id: return Color(red: 0.19, green: 0.67, blue: 0.45)
        case UsageSource.claude.id: return Color(red: 0.88, green: 0.38, blue: 0.27)
        case UsageSource.kimi.id: return Color(red: 0.12, green: 0.58, blue: 0.78)
        case UsageSource.omp.id: return Color(red: 0.82, green: 0.60, blue: 0.12)
        case UsageSource.openCode.id: return Color(red: 0.66, green: 0.36, blue: 0.72)
        case UsageSource.gemini.id: return Color(red: 0.25, green: 0.48, blue: 0.92)
        default:
            let palette: [Color] = [.mint, .pink, .indigo, .orange, .cyan, .green]
            let checksum = id.unicodeScalars.reduce(0) { $0 + Int($1.value) }
            return palette[checksum % palette.count]
        }
    }

    var symbolName: String {
        switch id {
        case UsageSource.codex.id: return "chevron.left.forwardslash.chevron.right"
        case UsageSource.claude.id: return "sparkles"
        case UsageSource.kimi.id: return "moon.stars.fill"
        case UsageSource.omp.id: return "bolt.horizontal.fill"
        case UsageSource.openCode.id: return "terminal.fill"
        case UsageSource.gemini.id: return "diamond.fill"
        default: return "cpu"
        }
    }
}
