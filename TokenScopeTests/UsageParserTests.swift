import XCTest
@testable import TokenScope

final class UsageParserTests: XCTestCase {
    func testCodexUsesCumulativeDeltasWithoutDoubleCounting() throws {
        let file = try fixture(
            name: "rollout-test.jsonl",
            contents: """
            {"timestamp":"2026-07-22T08:00:00.000Z","type":"turn_context","payload":{"model":"gpt-test"}}
            {"timestamp":"2026-07-22T08:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":30,"cache_write_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":120}}}}
            {"timestamp":"2026-07-22T08:01:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":30,"cache_write_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":120}}}}
            {"timestamp":"2026-07-22T08:02:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":150,"cached_input_tokens":50,"cache_write_input_tokens":0,"output_tokens":30,"reasoning_output_tokens":8,"total_tokens":180}}}}
            """
        )

        let events = try CodexUsageParser(rootURL: file.deletingLastPathComponent()).parse(file)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.reduce(0) { $0 + $1.tokens.total }, 180)
        XCTAssertEqual(events.last?.model, "gpt-test")
        XCTAssertEqual(events.last?.tokens.cacheRead, 20)
    }

    func testClaudeKeepsLargestRecordForRepeatedMessageID() throws {
        let file = try fixture(
            name: "claude.jsonl",
            contents: """
            {"timestamp":"2026-07-22T08:00:00.000Z","type":"assistant","uuid":"one","message":{"id":"msg-1","role":"assistant","model":"claude-test","usage":{"input_tokens":10,"cache_creation_input_tokens":3,"cache_read_input_tokens":20,"output_tokens":2}}}
            {"timestamp":"2026-07-22T08:00:01.000Z","type":"assistant","uuid":"two","message":{"id":"msg-1","role":"assistant","model":"claude-test","usage":{"input_tokens":10,"cache_creation_input_tokens":3,"cache_read_input_tokens":20,"output_tokens":4}}}
            """
        )

        let events = try ClaudeUsageParser(rootURL: file.deletingLastPathComponent()).parse(file)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.tokens.total, 37)
    }

    func testKimiOnlyCountsTurnUsageRecord() throws {
        let file = try fixture(
            name: "wire.jsonl",
            contents: """
            {"time":1784707200000,"type":"llm.response","usage":{"inputOther":10,"output":4,"inputCacheRead":20,"inputCacheCreation":0}}
            {"time":1784707201000,"type":"usage.record","model":"kimi-code/test","usageScope":"turn","usage":{"inputOther":10,"output":4,"inputCacheRead":20,"inputCacheCreation":2}}
            """
        )

        let events = try KimiUsageParser(rootURL: file.deletingLastPathComponent()).parse(file)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.tokens.total, 36)
        XCTAssertEqual(events.first?.model, "kimi-code/test")
    }

    func testOMPReadsUsageAndCost() throws {
        let file = try fixture(
            name: "omp.jsonl",
            contents: """
            {"id":"event-1","timestamp":"2026-07-22T08:00:00.000Z","type":"message","message":{"role":"assistant","provider":"xai","model":"grok-test","usage":{"input":100,"output":20,"cacheRead":30,"cacheWrite":4,"totalTokens":154,"cost":{"total":0.01}}}}
            """
        )

        let events = try OMPUsageParser(rootURL: file.deletingLastPathComponent()).parse(file)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.tokens.total, 154)
        XCTAssertEqual(events.first?.provider, "xai")
        XCTAssertEqual(events.first?.costUSD, 0.01)
    }

    func testOpenCodeReadsAssistantMessageUsage() throws {
        let file = try fixture(
            name: "msg_test.json",
            contents: """
            {"id":"msg-test","role":"assistant","providerID":"xai","modelID":"grok-test","time":{"created":1784707200000,"completed":1784707201000},"tokens":{"input":100,"output":20,"reasoning":5,"cache":{"read":30,"write":4}},"cost":0.02}
            """
        )

        let events = try OpenCodeUsageParser(rootURL: file.deletingLastPathComponent()).parse(file)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.source, .openCode)
        XCTAssertEqual(events.first?.tokens.total, 159)
        XCTAssertEqual(events.first?.tokens.reasoning, 5)
    }

    func testGeminiNormalizesCachedAndThoughtTokens() throws {
        let file = try fixture(
            name: "session-test.json",
            contents: """
            {"messages":[{"id":"gemini-test","type":"gemini","timestamp":"2026-07-22T08:00:00.000Z","model":"gemini-test","tokens":{"input":100,"output":20,"cached":30,"thoughts":5,"tool":2,"total":127}}]}
            """
        )

        let events = try GeminiUsageParser(rootURL: file.deletingLastPathComponent()).parse(file)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.source, .gemini)
        XCTAssertEqual(events.first?.tokens.total, 127)
        XCTAssertEqual(events.first?.tokens.input, 70)
    }

    func testSummaryContainsOnlySourcesWithEvents() {
        let event = UsageEvent(
            id: "one",
            timestamp: Date(),
            source: .codex,
            provider: "OpenAI",
            model: "test",
            tokens: TokenBreakdown(input: 10, output: 2),
            costUSD: nil
        )

        let summary = UsageSummary.make(from: [event])
        XCTAssertEqual(summary.sources.map(\SourceUsageSummary.source), [.codex])
    }

    func testDailySummaryGroupsEventsByCalendarDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        let firstDay = calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 23))!
        let secondDay = calendar.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 1))!

        let events = [
            UsageEvent(
                id: "first",
                timestamp: firstDay,
                source: .codex,
                provider: "OpenAI",
                model: "test",
                tokens: TokenBreakdown(input: 10, output: 2),
                costUSD: nil
            ),
            UsageEvent(
                id: "second",
                timestamp: secondDay,
                source: .kimi,
                provider: "Moonshot",
                model: "test",
                tokens: TokenBreakdown(input: 20, output: 3),
                costUSD: nil
            )
        ]

        let days = DailyUsageSummary.make(from: events, calendar: calendar)

        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days.map(\.tokens.total), [12, 23])
        XCTAssertEqual(days.map(\.sources.first?.source), [.codex, .kimi])
        XCTAssertEqual(days.map { calendar.component(.day, from: $0.date) }, [21, 22])
    }

    func testWidgetSnapshotUsesTodayAndMonthBoundaries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        let generatedAt = calendar.date(from: DateComponents(year: 2026, month: 7, day: 23, hour: 12))!
        let yesterday = calendar.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 22))!
        let today = calendar.date(from: DateComponents(year: 2026, month: 7, day: 23, hour: 9))!
        let events = [
            UsageEvent(
                id: "yesterday",
                timestamp: yesterday,
                source: .claude,
                provider: "Anthropic",
                model: "test",
                tokens: TokenBreakdown(input: 100, output: 20),
                costUSD: nil
            ),
            UsageEvent(
                id: "today",
                timestamp: today,
                source: .codex,
                provider: "OpenAI",
                model: "test",
                tokens: TokenBreakdown(input: 30, output: 5, cacheRead: 10),
                costUSD: nil
            )
        ]

        let snapshot = WidgetSnapshotPublisher.makeSnapshot(
            from: events,
            generatedAt: generatedAt,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.range, .today)
        XCTAssertEqual(snapshot.displayedTokens, 35)
        XCTAssertFalse(snapshot.includesCache)
        XCTAssertEqual(snapshot.todayTokens, 35)
        XCTAssertEqual(snapshot.monthTokens, 155)
        XCTAssertEqual(snapshot.inputTokens, 30)
        XCTAssertEqual(snapshot.cacheTokens, 10)
        XCTAssertEqual(snapshot.callCount, 1)
        XCTAssertEqual(snapshot.agents.map(\.id), ["codex"])

        let cachedSnapshot = WidgetSnapshotPublisher.makeSnapshot(
            from: events,
            includesCache: true,
            generatedAt: generatedAt,
            calendar: calendar
        )
        XCTAssertTrue(cachedSnapshot.includesCache)
        XCTAssertEqual(cachedSnapshot.todayTokens, 45)
        XCTAssertEqual(cachedSnapshot.monthTokens, 165)

        let monthSnapshot = WidgetSnapshotPublisher.makeSnapshot(
            from: events,
            range: .month,
            generatedAt: generatedAt,
            calendar: calendar
        )
        XCTAssertEqual(monthSnapshot.range, .month)
        XCTAssertEqual(monthSnapshot.displayedTokens, 155)
        XCTAssertEqual(monthSnapshot.todayTokens, 155)
        XCTAssertEqual(monthSnapshot.actualTodayTokens, 35)
        XCTAssertEqual(monthSnapshot.inputTokens, 130)
        XCTAssertEqual(monthSnapshot.outputTokens, 25)
        XCTAssertEqual(monthSnapshot.callCount, 2)
        XCTAssertEqual(Set(monthSnapshot.agents.map(\.id)), Set(["claude", "codex"]))

        let newerSameContent = WidgetSnapshotPublisher.makeSnapshot(
            from: events,
            generatedAt: generatedAt.addingTimeInterval(60),
            calendar: calendar
        )
        XCTAssertTrue(snapshot.hasSameDisplayContent(as: newerSameContent))
        XCTAssertFalse(snapshot.hasSameDisplayContent(as: monthSnapshot))
        XCTAssertFalse(snapshot.isStale(relativeTo: generatedAt.addingTimeInterval(14 * 60)))
        XCTAssertTrue(snapshot.isStale(relativeTo: generatedAt.addingTimeInterval(16 * 60)))

        let staleDataFreshRange = WidgetSnapshotPublisher.makeSnapshot(
            from: events,
            generatedAt: yesterday,
            referenceDate: generatedAt,
            calendar: calendar
        )
        XCTAssertEqual(staleDataFreshRange.generatedAt, yesterday)
        XCTAssertEqual(staleDataFreshRange.todayTokens, 35)
    }

    func testScannerDetectsAgentDirectoryCreatedAfterInitialization() throws {
        let homeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: homeDirectory) }

        let scanner = UsageScanner(homeDirectory: homeDirectory)
        let sessions = homeDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

        let now = Date()
        let timestamp = ISO8601DateFormatter().string(from: now)
        let log = sessions.appendingPathComponent("rollout-late.jsonl")
        let contents = """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":12,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":3,"reasoning_output_tokens":0,"total_tokens":15}}}}
        """
        try XCTUnwrap(contents.data(using: .utf8)).write(to: log)

        let result = scanner.scan(since: now.addingTimeInterval(-60), now: now)

        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events.first?.source, .codex)
        XCTAssertEqual(result.events.first?.tokens.total, 15)
        XCTAssertEqual(result.statuses[.codex]?.isAvailable, true)
    }

    private func fixture(name: String, contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(name)
        try contents.data(using: .utf8)?.write(to: file)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return file
    }
}
