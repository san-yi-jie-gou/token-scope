import Foundation

struct UsageSource: Hashable, Codable, Identifiable {
    let id: String
    let displayName: String

    static let codex = UsageSource(id: "codex", displayName: "Codex")
    static let claude = UsageSource(id: "claude", displayName: "Claude")
    static let kimi = UsageSource(id: "kimi", displayName: "Kimi")
    static let omp = UsageSource(id: "omp", displayName: "OMP")
    static let openCode = UsageSource(id: "opencode", displayName: "OpenCode")
    static let gemini = UsageSource(id: "gemini", displayName: "Gemini")
    static let copilot = UsageSource(id: "copilot", displayName: "Copilot")
    static let cursor = UsageSource(id: "cursor", displayName: "Cursor")
    static let qoder = UsageSource(id: "qoder", displayName: "Qoder")
    static let windsurf = UsageSource(id: "windsurf", displayName: "Windsurf")
    static let cline = UsageSource(id: "cline", displayName: "Cline")
    static let trae = UsageSource(id: "trae", displayName: "Trae")
}

struct TokenBreakdown: Equatable, Codable {
    var input: Int64 = 0
    var output: Int64 = 0
    var cacheRead: Int64 = 0
    var cacheWrite: Int64 = 0
    var reasoning: Int64 = 0

    var total: Int64 {
        total(includingCache: true)
    }

    func total(includingCache: Bool) -> Int64 {
        let uncached = max(0, input) + max(0, output)
        guard includingCache else { return uncached }
        return uncached + max(0, cacheRead) + max(0, cacheWrite)
    }

    static func + (lhs: TokenBreakdown, rhs: TokenBreakdown) -> TokenBreakdown {
        TokenBreakdown(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
            reasoning: lhs.reasoning + rhs.reasoning
        )
    }

    func delta(from previous: TokenBreakdown) -> TokenBreakdown? {
        guard input >= previous.input,
              output >= previous.output,
              cacheRead >= previous.cacheRead,
              cacheWrite >= previous.cacheWrite,
              reasoning >= previous.reasoning else {
            return nil
        }

        return TokenBreakdown(
            input: input - previous.input,
            output: output - previous.output,
            cacheRead: cacheRead - previous.cacheRead,
            cacheWrite: cacheWrite - previous.cacheWrite,
            reasoning: reasoning - previous.reasoning
        )
    }
}

struct UsageEvent: Identifiable, Equatable {
    let id: String
    let timestamp: Date
    let source: UsageSource
    let provider: String
    let model: String
    let tokens: TokenBreakdown
    let costUSD: Double?
}

struct SourceStatus: Equatable {
    let source: UsageSource
    let isAvailable: Bool
    let fileCount: Int
    let eventCount: Int
    let errorCount: Int
}

struct ScanResult {
    let events: [UsageEvent]
    let statuses: [UsageSource: SourceStatus]
    let scannedAt: Date
}

enum UsageRange: String, CaseIterable, Identifiable {
    case today
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return L10n.string("range.today")
        case .month: return L10n.string("range.month")
        }
    }

    func startDate(relativeTo date: Date = Date(), calendar: Calendar = .current) -> Date {
        switch self {
        case .today:
            return calendar.startOfDay(for: date)
        case .month:
            return calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        }
    }
}

struct SourceUsageSummary: Identifiable, Equatable {
    let source: UsageSource
    let tokens: TokenBreakdown
    let eventCount: Int

    var id: UsageSource { source }
}

struct UsageSummary: Equatable {
    let tokens: TokenBreakdown
    let sources: [SourceUsageSummary]
    let eventCount: Int

    static let empty = UsageSummary(
        tokens: TokenBreakdown(),
        sources: [],
        eventCount: 0
    )

    static func make(from events: [UsageEvent], includingCache: Bool = true) -> UsageSummary {
        let total = events.reduce(into: TokenBreakdown()) { result, event in
            result = result + event.tokens
        }

        let sourceSummaries = Dictionary(grouping: events, by: \UsageEvent.source)
            .map { source, sourceEvents in
                let sourceTotal = sourceEvents.reduce(into: TokenBreakdown()) { result, event in
                    result = result + event.tokens
                }
                return SourceUsageSummary(source: source, tokens: sourceTotal, eventCount: sourceEvents.count)
            }
            .filter { $0.tokens.total(includingCache: includingCache) > 0 }
            .sorted {
                let lhsTotal = $0.tokens.total(includingCache: includingCache)
                let rhsTotal = $1.tokens.total(includingCache: includingCache)
                if lhsTotal == rhsTotal {
                    return $0.source.displayName < $1.source.displayName
                }
                return lhsTotal > rhsTotal
            }

        return UsageSummary(tokens: total, sources: sourceSummaries, eventCount: events.count)
    }
}

struct DailyUsageSummary: Identifiable, Equatable {
    let date: Date
    let tokens: TokenBreakdown
    let sources: [SourceUsageSummary]
    let eventCount: Int

    var id: Date { date }

    static func make(
        from events: [UsageEvent],
        includingCache: Bool = true,
        calendar: Calendar = .current
    ) -> [DailyUsageSummary] {
        Dictionary(grouping: events) { event in
            calendar.startOfDay(for: event.timestamp)
        }
        .map { date, dayEvents in
            let summary = UsageSummary.make(from: dayEvents, includingCache: includingCache)
            return DailyUsageSummary(
                date: date,
                tokens: summary.tokens,
                sources: summary.sources,
                eventCount: summary.eventCount
            )
        }
        .filter { $0.tokens.total(includingCache: includingCache) > 0 }
        .sorted { $0.date < $1.date }
    }
}
