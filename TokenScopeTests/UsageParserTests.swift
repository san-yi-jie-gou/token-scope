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

    func testGenericParserReadsCopilotStyleUsageJSONL() throws {
        let file = try fixture(
            name: "copilot-usage.jsonl",
            contents: """
            {"id":"request-1","timestamp":"2026-07-22T08:00:00.000Z","provider":"GitHub","model":"gpt-test","usage":{"promptTokens":100,"completionTokens":20,"cachedTokens":30,"reasoningTokens":5,"totalCost":0.03}}
            """
        )

        let events = try GenericUsageLogParser(
            source: .copilot,
            rootURL: file.deletingLastPathComponent(),
            provider: "GitHub",
            modelFallback: "GitHub Copilot"
        ).parse(file)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.source, .copilot)
        XCTAssertEqual(events.first?.provider, "GitHub")
        XCTAssertEqual(events.first?.model, "gpt-test")
        XCTAssertEqual(events.first?.tokens.total, 155)
        XCTAssertEqual(events.first?.tokens.reasoning, 5)
        XCTAssertEqual(events.first?.costUSD, 0.03)
    }

    func testGenericParserFindsNestedAgentUsageJSON() throws {
        let file = try fixture(
            name: "cursor-chat-history.json",
            contents: """
            {"sessions":[{"id":"turn-1","createdAt":"2026-07-22T08:00:00.000Z","modelID":"claude-test","messages":[{"role":"assistant","tokenUsage":{"input_tokens":40,"output_tokens":8,"cache_read_tokens":12,"cache_write_tokens":2}}]}]}
            """
        )

        let events = try GenericUsageLogParser(
            source: .cursor,
            rootURL: file.deletingLastPathComponent(),
            provider: "Cursor",
            modelFallback: "Cursor"
        ).parse(file)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.source, .cursor)
        XCTAssertEqual(events.first?.model, "claude-test")
        XCTAssertEqual(events.first?.tokens.total, 62)
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

    func testScannerRefreshesChangedOpenCodeMessage() throws {
        let homeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let messageDirectory = homeDirectory
            .appendingPathComponent(".local/share/opencode/storage/message/session-test", isDirectory: true)
        try FileManager.default.createDirectory(at: messageDirectory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: homeDirectory) }

        let now = Date()
        let timestamp = Int(now.timeIntervalSince1970 * 1_000)
        let message = messageDirectory.appendingPathComponent("msg_test.json")
        try openCodeMessage(id: "first", timestamp: timestamp, input: 10).write(to: message)

        let scanner = UsageScanner(homeDirectory: homeDirectory)
        let first = scanner.scan(since: now.addingTimeInterval(-60), now: now)
        XCTAssertEqual(first.events.first?.tokens.total, 12)

        try openCodeMessage(id: "first", timestamp: timestamp, input: 100).write(to: message)
        let second = scanner.scan(since: now.addingTimeInterval(-60), now: now)
        XCTAssertEqual(second.events.first?.tokens.total, 102)
    }

    func testScannerLimitsConcurrentSourceParsing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let probe = ConcurrentParseProbe()
        let sources: [UsageSource] = [.codex, .claude, .kimi]
        let parsers = try sources.map { source in
            let directory = root.appendingPathComponent(source.id, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("log.json")
            try Data("{}".utf8).write(to: file)
            return SlowUsageParser(source: source, rootURL: directory, probe: probe)
        }
        let scanner = UsageScanner(parsers: parsers, maximumConcurrentSources: 2)
        let finished = expectation(description: "scan finished")

        DispatchQueue.global().async {
            _ = scanner.scan(since: Date().addingTimeInterval(-60))
            finished.fulfill()
        }

        XCTAssertTrue(probe.waitForEntries(2))
        XCTAssertEqual(probe.maximumActiveParsers, 2)
        probe.releaseParsers(count: 3)
        wait(for: [finished], timeout: 2)
    }

    func testStorePrioritizesTodayBeforeMonthBackfill() {
        let now = Date(timeIntervalSince1970: 1_784_885_600)
        let defaults = isolatedDefaults()
        defaults.set(UsageRange.today.rawValue, forKey: "usageRange")
        let scanner = RecordingScanner(now: now)
        let store = UsageStore(
            scanner: scanner,
            defaults: defaults,
            snapshotPublisher: { _, _, _, _, _ in }
        ) { now }

        store.refresh()

        XCTAssertTrue(waitUntil { scanner.requestedStarts.count >= 2 })
        XCTAssertEqual(scanner.requestedStarts[0], UsageRange.today.startDate(relativeTo: now))
        XCTAssertEqual(scanner.requestedStarts[1], UsageRange.month.startDate(relativeTo: now))
        XCTAssertEqual(store.lastUpdated, now)
    }

    func testStoreScansMonthImmediatelyWhenMonthIsSelected() {
        let now = Date(timeIntervalSince1970: 1_784_885_600)
        let defaults = isolatedDefaults()
        defaults.set(UsageRange.month.rawValue, forKey: "usageRange")
        let scanner = RecordingScanner(now: now)
        let store = UsageStore(
            scanner: scanner,
            defaults: defaults,
            snapshotPublisher: { _, _, _, _, _ in }
        ) { now }

        store.refresh()

        XCTAssertTrue(waitUntil { store.lastUpdated == now })
        XCTAssertEqual(scanner.requestedStarts[0], UsageRange.month.startDate(relativeTo: now))
        XCTAssertEqual(store.lastUpdated, now)
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

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "TokenScopeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    private func openCodeMessage(id: String, timestamp: Int, input: Int) throws -> Data {
        let object: [String: Any] = [
            "id": id,
            "role": "assistant",
            "providerID": "OpenCode",
            "modelID": "test",
            "time": ["completed": timestamp],
            "tokens": ["input": input, "output": 2]
        ]
        return try JSONSerialization.data(withJSONObject: object)
    }
}

private final class RecordingScanner: UsageScanning {
    private let lock = NSLock()
    private var starts: [Date] = []
    private let now: Date

    var requestedStarts: [Date] {
        lock.lock()
        defer { lock.unlock() }
        return starts
    }

    init(now: Date) {
        self.now = now
    }

    func scan(since startDate: Date) -> ScanResult {
        lock.lock()
        starts.append(startDate)
        lock.unlock()

        let event = UsageEvent(
            id: "recording-\(startDate.timeIntervalSince1970)",
            timestamp: now.addingTimeInterval(-60),
            source: .codex,
            provider: "OpenAI",
            model: "test",
            tokens: TokenBreakdown(input: 10, output: 2),
            costUSD: nil
        )

        return ScanResult(
            events: [event],
            statuses: [
                .codex: SourceStatus(
                    source: .codex,
                    isAvailable: true,
                    fileCount: 1,
                    eventCount: 1,
                    errorCount: 0
                )
            ],
            scannedAt: now
        )
    }
}

private final class ConcurrentParseProbe {
    private let lock = NSLock()
    private let entered = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)
    private var activeParsers = 0
    private var maximumActive = 0

    var maximumActiveParsers: Int {
        lock.lock()
        defer { lock.unlock() }
        return maximumActive
    }

    func enter() {
        lock.lock()
        activeParsers += 1
        maximumActive = max(maximumActive, activeParsers)
        lock.unlock()
        entered.signal()
        release.wait()
        lock.lock()
        activeParsers -= 1
        lock.unlock()
    }

    func waitForEntries(_ count: Int) -> Bool {
        for _ in 0..<count {
            guard entered.wait(timeout: .now() + 1) == .success else { return false }
        }
        return true
    }

    func releaseParsers(count: Int) {
        for _ in 0..<count {
            release.signal()
        }
    }
}

private struct SlowUsageParser: UsageLogParser {
    let source: UsageSource
    let rootURL: URL
    let probe: ConcurrentParseProbe

    func accepts(_ url: URL) -> Bool {
        url.lastPathComponent == "log.json"
    }

    func parse(_ url: URL) throws -> [UsageEvent] {
        probe.enter()
        return []
    }
}
