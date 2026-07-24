import AppKit
import Charts
import SwiftUI

private enum TokenScopeStyle {
    static let accent = Color(red: 0.15, green: 0.68, blue: 0.58)
    static let cornerRadius: CGFloat = 10
    static let ringDiameter: CGFloat = 166
}

struct DesktopWidgetView: View {
    @ObservedObject var store: UsageStore
    let onHide: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highlightedSourceID: String?

    private var summary: UsageSummary { store.summary }
    private var displayedTotal: Int64 {
        summary.tokens.total(includingCache: store.includesCache)
    }
    private var effectiveHighlightedSourceID: String? {
        guard let highlightedSourceID,
              summary.sources.contains(where: { $0.source.id == highlightedSourceID }) else {
            return nil
        }
        return highlightedSourceID
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .opacity(0.5)

            energyCoreSection

            if store.range == .month && !store.dailyUsage.isEmpty {
                MonthlyUsageChart(days: store.dailyUsage, includesCache: store.includesCache)
                    .frame(height: WidgetLayout.monthChartHeight)
            }

            sourceRows
            footer
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(
            width: WidgetLayout.width,
            height: WidgetLayout.height(activeAgentCount: summary.sources.count, range: store.range),
            alignment: .top
        )
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: TokenScopeStyle.cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: TokenScopeStyle.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
        }
        .contextMenu {
            Button("隐藏", systemImage: "eye.slash") { onHide() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("TokenScope")
                    .font(.system(size: 15, weight: .semibold))
                Text("本地 AI Token 用量")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 6)

            Picker("统计周期", selection: $store.range) {
                ForEach(UsageRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 108)

            Button {
                store.refresh(userInitiated: true)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(store.isRefreshing && !reduceMotion ? 360 : 0))
                    .animation(
                        store.isRefreshing && !reduceMotion
                            ? .linear(duration: 1).repeatForever(autoreverses: false)
                            : .default,
                        value: store.isRefreshing
                    )
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(store.isRefreshing || !store.hasDataDirectoryAccess)
            .help("刷新用量")
            .accessibilityLabel("刷新用量")
        }
        .frame(height: 40)
    }

    private var energyCoreSection: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(
                        TokenScopeStyle.accent.opacity(0.24),
                        style: StrokeStyle(lineWidth: 1, dash: [24, 14])
                    )
                    .frame(width: 184, height: 184)

                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(TokenScopeStyle.accent.opacity(0.58))
                        .frame(width: 2, height: 9)
                        .offset(y: -92)
                        .rotationEffect(.degrees(Double(index) * 90))
                }

                EnergyRing(
                    sources: summary.sources,
                    grandTotal: displayedTotal,
                    includesCache: store.includesCache,
                    highlightedSourceID: effectiveHighlightedSourceID
                )
                .frame(width: TokenScopeStyle.ringDiameter, height: TokenScopeStyle.ringDiameter)

                VStack(spacing: 3) {
                    Text("TOKEN 能量")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(TokenScopeStyle.accent)

                    Text(TokenFormatter.compact(displayedTotal))
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(displayedTotal)))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text("tokens")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    if displayedTotal > 0 {
                        Text("\(TokenFormatter.compact(Int64(summary.eventCount))) 次调用")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(TokenScopeStyle.accent)
                            .monospacedDigit()
                    }
                }
                .frame(width: 112)
            }
            .frame(width: 190, height: 184)

            Text(coreCaption)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(height: WidgetLayout.energyCoreHeight)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: effectiveHighlightedSourceID)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("总消耗 \(TokenFormatter.compact(displayedTotal)) tokens，\(coreCaption)")
    }

    private var coreCaption: String {
        guard displayedTotal > 0,
              let source = highlightedSource
        else {
            return store.range == .today ? "今天暂无来源" : "本月暂无来源"
        }
        return "\(source.source.displayName) 占比 \(percentageLabel(for: source))"
    }

    private var highlightedSource: SourceUsageSummary? {
        if let effectiveHighlightedSourceID {
            return summary.sources.first { $0.source.id == effectiveHighlightedSourceID }
        }
        return summary.sources.first
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if summary.sources.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                    Text(store.range == .today ? "今天还没有 Token 记录" : "本月还没有 Token 记录")
                }
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    ForEach(summary.sources) { item in
                        SourceChannelRow(
                            summary: item,
                            grandTotal: displayedTotal,
                            includesCache: store.includesCache,
                            isHighlighted: effectiveHighlightedSourceID == item.source.id
                        ) { isHovered in
                            highlightedSourceID = isHovered ? item.source.id : nil
                        }
                    }
                }
            }
        }
        .frame(height: WidgetLayout.sourceRowsHeight(activeAgentCount: summary.sources.count))
    }

    private var footer: some View {
        HStack(spacing: 9) {
            MetricLabel(systemImage: "arrow.up", title: "输入", value: summary.tokens.input)
            MetricLabel(systemImage: "arrow.down", title: "输出", value: summary.tokens.output)
            MetricLabel(
                systemImage: "internaldrive",
                title: "缓存",
                value: summary.tokens.cacheRead + summary.tokens.cacheWrite
            )

            Spacer(minLength: 2)

            if let lastUpdated = store.lastUpdated {
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                    Text(lastUpdated, format: .dateTime.hour().minute())
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
            } else if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(height: WidgetLayout.footerHeight)
        .overlay(alignment: .top) {
            Divider().opacity(0.5)
        }
    }

    private func percentageLabel(for item: SourceUsageSummary) -> String {
        guard displayedTotal > 0 else { return "0%" }
        let value = item.tokens.total(includingCache: store.includesCache)
        let percentage = Double(value) / Double(displayedTotal) * 100
        return percentage < 0.1 ? "<0.1%" : String(format: "%.1f%%", percentage)
    }
}

private struct RingSegment: Identifiable {
    let id: String
    let color: Color
    let start: Double
    let end: Double
}

private struct EnergyRing: View {
    let sources: [SourceUsageSummary]
    let grandTotal: Int64
    let includesCache: Bool
    let highlightedSourceID: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var segments: [RingSegment] {
        guard grandTotal > 0 else { return [] }
        var cursor = 0.0
        return sources.compactMap { item in
            let value = max(0, item.tokens.total(includingCache: includesCache))
            guard value > 0 else { return nil }
            let fraction = Double(value) / Double(grandTotal)
            let segment = RingSegment(
                id: item.source.id,
                color: item.source.tint,
                start: cursor,
                end: min(1, cursor + fraction)
            )
            cursor += fraction
            return segment
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 15)

            ForEach(segments) { segment in
                let length = segment.end - segment.start
                let gap = min(0.004, length * 0.22)

                Circle()
                    .trim(from: segment.start + gap, to: max(segment.start + gap, segment.end - gap))
                    .stroke(
                        segment.color,
                        style: StrokeStyle(lineWidth: 15, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .opacity(
                        highlightedSourceID == nil || highlightedSourceID == segment.id ? 1 : 0.2
                    )
            }
        }
        .shadow(color: TokenScopeStyle.accent.opacity(0.12), radius: 8)
        .animation(reduceMotion ? nil : .snappy(duration: 0.32), value: segments.map(\.end))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: highlightedSourceID)
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
        VStack(spacing: 5) {
            HStack {
                Text("每日消耗")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                Group {
                    if let hoveredDay {
                        HStack(spacing: 3) {
                            Text(hoveredDay.date, format: .dateTime.month().day())
                            Text("·")
                            Text(TokenFormatter.compact(chartTotal(hoveredDay.tokens)))
                                .fontWeight(.semibold)
                            Text("· \(hoveredDay.eventCount) 次")
                        }
                    } else {
                        Text("峰值 \(TokenFormatter.compact(peak))")
                    }
                }
                .font(.system(size: 9, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            }

            Chart {
                ForEach(days) { day in
                    ForEach(day.sources.sorted { $0.source.id < $1.source.id }) { source in
                        BarMark(
                            x: .value("日期", day.date, unit: .day),
                            y: .value("Tokens", chartTotal(source.tokens))
                        )
                        .foregroundStyle(source.source.tint)
                        .cornerRadius(1)
                        .opacity(barOpacity(for: day))
                    }
                }

                if let hoveredDay {
                    RuleMark(x: .value("选中日期", hoveredDay.date, unit: .day))
                        .foregroundStyle(TokenScopeStyle.accent.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartXScale(domain: chartDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { value in
                    AxisValueLabel(format: .dateTime.day())
                        .foregroundStyle(Color.secondary.opacity(0.65))
                }
            }
            .chartYAxis(.hidden)
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
            .frame(height: 52)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: includesCache)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hoveredDate)
            .accessibilityLabel("本月每日 Token 消耗")
            .accessibilityValue("峰值 \(TokenFormatter.compact(peak))")
        }
    }

    private func barOpacity(for day: DailyUsageSummary) -> Double {
        guard let hoveredDate else { return 0.78 }
        return Calendar.current.isDate(day.date, inSameDayAs: hoveredDate) ? 1 : 0.2
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

private struct SourceChannelRow: View {
    let summary: SourceUsageSummary
    let grandTotal: Int64
    let includesCache: Bool
    let isHighlighted: Bool
    let onHoverChange: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var displayedTotal: Int64 {
        summary.tokens.total(includingCache: includesCache)
    }

    private var percentage: Double {
        guard grandTotal > 0 else { return 0 }
        return Double(displayedTotal) / Double(grandTotal) * 100
    }

    private var percentageLabel: String {
        percentage < 0.1 ? "<0.1%" : String(format: "%.1f%%", percentage)
    }

    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 1)
                .fill(summary.source.tint)
                .frame(width: 7, height: 7)
                .rotationEffect(.degrees(45))

            Image(systemName: summary.source.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(summary.source.tint)
                .frame(width: 14)

            Text(summary.source.displayName)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(percentageLabel)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            Spacer(minLength: 4)

            Text(TokenFormatter.compact(displayedTotal))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(displayedTotal)))
        }
        .padding(.horizontal, 2)
        .frame(height: WidgetLayout.sourceRowHeight)
        .background(summary.source.tint.opacity(isHighlighted ? 0.07 : 0))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.45)
        }
        .contentShape(Rectangle())
        .onHover(perform: onHoverChange)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHighlighted)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(summary.source.displayName)，\(TokenFormatter.compact(displayedTotal)) tokens，占比 \(percentageLabel)"
        )
    }
}

private struct MetricLabel: View {
    let systemImage: String
    let title: String
    let value: Int64

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(title)
                .foregroundStyle(.tertiary)
            Text(TokenFormatter.compact(value))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 9))
        .fixedSize()
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
        case UsageSource.copilot.id: return Color(red: 0.20, green: 0.55, blue: 0.86)
        case UsageSource.cursor.id: return Color(red: 0.12, green: 0.12, blue: 0.14)
        case UsageSource.qoder.id: return Color(red: 0.58, green: 0.42, blue: 0.95)
        case UsageSource.windsurf.id: return Color(red: 0.08, green: 0.62, blue: 0.72)
        case UsageSource.cline.id: return Color(red: 0.78, green: 0.36, blue: 0.42)
        case UsageSource.trae.id: return Color(red: 0.95, green: 0.48, blue: 0.20)
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
        case UsageSource.copilot.id: return "person.2.fill"
        case UsageSource.cursor.id: return "cursorarrow.rays"
        case UsageSource.qoder.id: return "q.square.fill"
        case UsageSource.windsurf.id: return "wind"
        case UsageSource.cline.id: return "hammer.fill"
        case UsageSource.trae.id: return "network"
        default: return "cpu"
        }
    }
}
