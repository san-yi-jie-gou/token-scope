import Foundation
import WidgetKit

enum WidgetSnapshotPublisher {
    static func publish(
        events: [UsageEvent],
        includesCache: Bool,
        range: UsageRange,
        generatedAt: Date = Date(),
        referenceDate: Date? = nil
    ) {
        let snapshot = makeSnapshot(
            from: events,
            includesCache: includesCache,
            range: range,
            generatedAt: generatedAt,
            referenceDate: referenceDate
        )
        if WidgetSnapshotServer.shared.update(snapshot) {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetBridge.widgetKind)
        }
    }

    static func makeSnapshot(
        from events: [UsageEvent],
        includesCache: Bool = false,
        range: UsageRange = .today,
        generatedAt: Date = Date(),
        referenceDate: Date? = nil,
        calendar: Calendar = .current
    ) -> WidgetUsageSnapshot {
        let rangeReferenceDate = referenceDate ?? generatedAt
        let todayStart = calendar.startOfDay(for: rangeReferenceDate)
        let monthStart = calendar.dateInterval(of: .month, for: rangeReferenceDate)?.start ?? todayStart
        let todaySummary = UsageSummary.make(
            from: events.filter { $0.timestamp >= todayStart },
            includingCache: includesCache
        )
        let monthSummary = UsageSummary.make(
            from: events.filter { $0.timestamp >= monthStart },
            includingCache: includesCache
        )
        let displayedSummary: UsageSummary
        switch range {
        case .today:
            displayedSummary = todaySummary
        case .month:
            displayedSummary = monthSummary
        }
        let todayTotal = todaySummary.tokens.total(includingCache: includesCache)
        let monthTotal = monthSummary.tokens.total(includingCache: includesCache)
        let selectedTotal = displayedSummary.tokens.total(includingCache: includesCache)

        return WidgetUsageSnapshot(
            generatedAt: generatedAt,
            range: range.widgetRange,
            includesCache: includesCache,
            // Keep the legacy field aligned with the selected period so an
            // older installed widget cannot silently show a different range.
            todayTokens: selectedTotal,
            monthTokens: monthTotal,
            actualTodayTokens: todayTotal,
            selectedTokens: selectedTotal,
            inputTokens: displayedSummary.tokens.input,
            outputTokens: displayedSummary.tokens.output,
            cacheTokens: displayedSummary.tokens.cacheRead + displayedSummary.tokens.cacheWrite,
            callCount: displayedSummary.eventCount,
            agents: displayedSummary.sources.map {
                WidgetAgentUsage(
                    id: $0.source.id,
                    name: $0.source.displayName,
                    tokens: $0.tokens.total(includingCache: includesCache)
                )
            }
        )
    }
}

private extension UsageRange {
    var widgetRange: WidgetUsageRange {
        switch self {
        case .today: return .today
        case .month: return .month
        }
    }
}
