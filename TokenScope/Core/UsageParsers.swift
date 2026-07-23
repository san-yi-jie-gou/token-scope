import Foundation

protocol UsageLogParser {
    var source: UsageSource { get }
    var rootURL: URL { get }
    func accepts(_ url: URL) -> Bool
    func parse(_ url: URL) throws -> [UsageEvent]
}

struct CodexUsageParser: UsageLogParser {
    let source = UsageSource.codex
    let rootURL: URL

    func accepts(_ url: URL) -> Bool {
        url.pathExtension == "jsonl" && url.lastPathComponent.hasPrefix("rollout-")
    }

    func parse(_ url: URL) throws -> [UsageEvent] {
        var events: [UsageEvent] = []
        var previous: TokenBreakdown?
        var currentModel = "Codex"

        try JSONLineReader.forEachObject(at: url) { object, lineNumber in
            if object.string("type") == "turn_context",
               let model = object.dictionary("payload")?.string("model") {
                currentModel = model
            }

            guard let payload = object.dictionary("payload"),
                  payload.string("type") == "token_count",
                  let info = payload.dictionary("info"),
                  let total = info.dictionary("total_token_usage"),
                  let timestamp = LogDateParser.parse(object["timestamp"]) else {
                return
            }

            let rawInput = total.int64("input_tokens")
            let cacheRead = total.int64("cached_input_tokens")
            let cacheWrite = total.int64("cache_write_input_tokens")
            let snapshot = TokenBreakdown(
                input: max(0, rawInput - cacheRead - cacheWrite),
                output: total.int64("output_tokens"),
                cacheRead: cacheRead,
                cacheWrite: cacheWrite,
                reasoning: total.int64("reasoning_output_tokens")
            )

            let increment: TokenBreakdown
            if let previous {
                increment = snapshot.delta(from: previous) ?? snapshot
            } else {
                increment = snapshot
            }
            self.assign(&previous, snapshot)

            guard increment.total > 0 else { return }
            events.append(
                UsageEvent(
                    id: "codex:\(url.path):\(lineNumber)",
                    timestamp: timestamp,
                    source: .codex,
                    provider: "OpenAI",
                    model: currentModel,
                    tokens: increment,
                    costUSD: nil
                )
            )
        }

        return events
    }

    private func assign(_ target: inout TokenBreakdown?, _ value: TokenBreakdown) {
        target = value
    }
}

struct ClaudeUsageParser: UsageLogParser {
    let source = UsageSource.claude
    let rootURL: URL

    func accepts(_ url: URL) -> Bool {
        url.pathExtension == "jsonl"
    }

    func parse(_ url: URL) throws -> [UsageEvent] {
        var eventsByMessage: [String: UsageEvent] = [:]

        try JSONLineReader.forEachObject(at: url) { object, lineNumber in
            guard object.string("type") == "assistant",
                  let message = object.dictionary("message"),
                  message.string("role") == "assistant",
                  let usage = message.dictionary("usage"),
                  let timestamp = LogDateParser.parse(object["timestamp"]) else {
                return
            }

            let messageID = message.string("id") ?? object.string("uuid") ?? "line-\(lineNumber)"
            let tokens = TokenBreakdown(
                input: usage.int64("input_tokens"),
                output: usage.int64("output_tokens"),
                cacheRead: usage.int64("cache_read_input_tokens"),
                cacheWrite: usage.int64("cache_creation_input_tokens"),
                reasoning: 0
            )
            guard tokens.total > 0 else { return }

            let event = UsageEvent(
                id: "claude:\(url.path):\(messageID)",
                timestamp: timestamp,
                source: .claude,
                provider: "CC Switch",
                model: message.string("model") ?? "Claude",
                tokens: tokens,
                costUSD: nil
            )

            if let existing = eventsByMessage[messageID], existing.tokens.total > tokens.total {
                return
            }
            eventsByMessage[messageID] = event
        }

        return Array(eventsByMessage.values)
    }
}

struct KimiUsageParser: UsageLogParser {
    let source = UsageSource.kimi
    let rootURL: URL

    func accepts(_ url: URL) -> Bool {
        url.lastPathComponent == "wire.jsonl"
    }

    func parse(_ url: URL) throws -> [UsageEvent] {
        var events: [UsageEvent] = []

        try JSONLineReader.forEachObject(at: url) { object, lineNumber in
            guard object.string("type") == "usage.record",
                  object.string("usageScope") == "turn",
                  let usage = object.dictionary("usage"),
                  let timestamp = LogDateParser.parse(object["time"]) else {
                return
            }

            let tokens = TokenBreakdown(
                input: usage.int64("inputOther"),
                output: usage.int64("output"),
                cacheRead: usage.int64("inputCacheRead"),
                cacheWrite: usage.int64("inputCacheCreation"),
                reasoning: usage.int64("reasoning")
            )
            guard tokens.total > 0 else { return }

            events.append(
                UsageEvent(
                    id: "kimi:\(url.path):\(lineNumber)",
                    timestamp: timestamp,
                    source: .kimi,
                    provider: "Moonshot",
                    model: object.string("model") ?? "Kimi Code",
                    tokens: tokens,
                    costUSD: nil
                )
            )
        }

        return events
    }
}

struct OMPUsageParser: UsageLogParser {
    let source = UsageSource.omp
    let rootURL: URL

    func accepts(_ url: URL) -> Bool {
        url.pathExtension == "jsonl"
    }

    func parse(_ url: URL) throws -> [UsageEvent] {
        var eventsByMessage: [String: UsageEvent] = [:]

        try JSONLineReader.forEachObject(at: url) { object, lineNumber in
            guard object.string("type") == "message",
                  let message = object.dictionary("message"),
                  message.string("role") == "assistant",
                  let usage = message.dictionary("usage"),
                  let timestamp = LogDateParser.parse(object["timestamp"]) else {
                return
            }

            let messageID = object.string("id") ?? "line-\(lineNumber)"
            let tokens = TokenBreakdown(
                input: usage.int64("input"),
                output: usage.int64("output"),
                cacheRead: usage.int64("cacheRead"),
                cacheWrite: usage.int64("cacheWrite"),
                reasoning: usage.int64("reasoning")
            )
            guard tokens.total > 0 else { return }

            let event = UsageEvent(
                id: "omp:\(url.path):\(messageID)",
                timestamp: timestamp,
                source: .omp,
                provider: message.string("provider") ?? "OMP",
                model: message.string("model") ?? "Grok",
                tokens: tokens,
                costUSD: usage.dictionary("cost")?.double("total")
            )

            if let existing = eventsByMessage[messageID], existing.tokens.total > tokens.total {
                return
            }
            eventsByMessage[messageID] = event
        }

        return Array(eventsByMessage.values)
    }
}

struct OpenCodeUsageParser: UsageLogParser {
    let source = UsageSource.openCode
    let rootURL: URL

    func accepts(_ url: URL) -> Bool {
        url.pathExtension == "json" && url.lastPathComponent.hasPrefix("ses_")
    }

    func parse(_ url: URL) throws -> [UsageEvent] {
        if url.lastPathComponent.hasPrefix("msg_") {
            return try parseMessage(url)
        }

        let data = try Data(contentsOf: url)
        guard let session = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionID = session.string("id") else {
            return []
        }

        let storageRoot = rootURL.deletingLastPathComponent()
        let messageDirectory = storageRoot
            .appendingPathComponent("message", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
        let messageFiles = (try? FileManager.default.contentsOfDirectory(
            at: messageDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return try messageFiles
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("msg_") }
            .flatMap(parseMessage)
    }

    private func parseMessage(_ url: URL) throws -> [UsageEvent] {
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object.string("role") == "assistant",
              let usage = object.dictionary("tokens"),
              let time = object.dictionary("time"),
              let timestamp = LogDateParser.parse(time["completed"] ?? time["created"]) else {
            return []
        }

        let reasoning = usage.int64("reasoning")
        let cache = usage.dictionary("cache") ?? [:]
        let tokens = TokenBreakdown(
            input: usage.int64("input"),
            output: usage.int64("output") + reasoning,
            cacheRead: cache.int64("read"),
            cacheWrite: cache.int64("write"),
            reasoning: reasoning
        )
        guard tokens.total > 0 else { return [] }

        let messageID = object.string("id") ?? url.deletingPathExtension().lastPathComponent
        return [
            UsageEvent(
                id: "opencode:\(messageID)",
                timestamp: timestamp,
                source: .openCode,
                provider: object.string("providerID") ?? "OpenCode",
                model: object.string("modelID") ?? "OpenCode",
                tokens: tokens,
                costUSD: object.double("cost")
            )
        ]
    }
}

struct GeminiUsageParser: UsageLogParser {
    let source = UsageSource.gemini
    let rootURL: URL

    func accepts(_ url: URL) -> Bool {
        url.pathExtension == "json"
            && url.lastPathComponent.hasPrefix("session-")
            && url.deletingLastPathComponent().lastPathComponent == "chats"
    }

    func parse(_ url: URL) throws -> [UsageEvent] {
        let data = try Data(contentsOf: url)
        guard let session = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = session["messages"] as? [[String: Any]] else {
            return []
        }

        return messages.enumerated().compactMap { index, message in
            guard message.string("type") == "gemini",
                  let usage = message.dictionary("tokens"),
                  let timestamp = LogDateParser.parse(message["timestamp"]) else {
                return nil
            }

            let cacheRead = usage.int64("cached")
            let reasoning = usage.int64("thoughts")
            let toolTokens = usage.int64("tool")
            let tokens = TokenBreakdown(
                input: max(0, usage.int64("input") - cacheRead),
                output: usage.int64("output") + reasoning + toolTokens,
                cacheRead: cacheRead,
                cacheWrite: 0,
                reasoning: reasoning
            )
            guard tokens.total > 0 else { return nil }

            let messageID = message.string("id") ?? "\(url.lastPathComponent)-\(index)"
            return UsageEvent(
                id: "gemini:\(messageID)",
                timestamp: timestamp,
                source: .gemini,
                provider: "Google",
                model: message.string("model") ?? "Gemini",
                tokens: tokens,
                costUSD: nil
            )
        }
    }
}
