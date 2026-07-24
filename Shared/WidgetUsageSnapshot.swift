import Foundation

enum WidgetUsageRange: String, Codable, Equatable {
    case today
    case month

    var title: String {
        switch self {
        case .today: return L10n.string("range.today")
        case .month: return L10n.string("range.month")
        }
    }
}

struct WidgetAgentUsage: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let tokens: Int64
}

struct WidgetUsageSnapshot: Codable, Equatable {
    let generatedAt: Date
    let range: WidgetUsageRange
    let includesCache: Bool
    // todayTokens remains the legacy field consumed by older installed widgets.
    // The current-period value is carried separately so new widgets can keep
    // the actual today total available when the selected range is month.
    let todayTokens: Int64
    let monthTokens: Int64
    let actualTodayTokens: Int64
    let selectedTokens: Int64
    let inputTokens: Int64
    let outputTokens: Int64
    let cacheTokens: Int64
    let callCount: Int
    let agents: [WidgetAgentUsage]

    var displayedTokens: Int64 {
        selectedTokens
    }

    var alternateRangeTitle: String {
        switch range {
        case .today: return WidgetUsageRange.month.title
        case .month: return WidgetUsageRange.today.title
        }
    }

    var alternateTokens: Int64 {
        switch range {
        case .today: return monthTokens
        case .month: return actualTodayTokens
        }
    }

    func isStale(
        relativeTo date: Date = Date(),
        threshold: TimeInterval = 15 * 60
    ) -> Bool {
        date.timeIntervalSince(generatedAt) > threshold
    }

    func hasSameDisplayContent(as other: WidgetUsageSnapshot) -> Bool {
        range == other.range
            && includesCache == other.includesCache
            && todayTokens == other.todayTokens
            && monthTokens == other.monthTokens
            && actualTodayTokens == other.actualTodayTokens
            && selectedTokens == other.selectedTokens
            && inputTokens == other.inputTokens
            && outputTokens == other.outputTokens
            && cacheTokens == other.cacheTokens
            && callCount == other.callCount
            && agents == other.agents
    }

    static let empty = WidgetUsageSnapshot(
        generatedAt: .distantPast,
        range: .today,
        includesCache: false,
        todayTokens: 0,
        monthTokens: 0,
        actualTodayTokens: 0,
        selectedTokens: 0,
        inputTokens: 0,
        outputTokens: 0,
        cacheTokens: 0,
        callCount: 0,
        agents: []
    )
}

enum WidgetBridge {
    static let widgetKind = "TokenScopeWidget"
    static let port: UInt16 = 47_833
}
