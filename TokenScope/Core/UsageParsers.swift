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
        url.pathExtension == "json"
            && url.lastPathComponent.hasPrefix("msg_")
            && url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "message"
    }

    func parse(_ url: URL) throws -> [UsageEvent] {
        try parseMessage(url)
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

struct GenericUsageLogParser: UsageLogParser {
    let source: UsageSource
    let rootURL: URL
    let provider: String
    let modelFallback: String

    func accepts(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        guard ["json", "jsonl", "log"].contains(fileExtension) else { return false }

        let path = url.path.lowercased()
        let usageHints = [
            "usage",
            "token",
            "session",
            "chat",
            "conversation",
            "history",
            "message",
            "request",
            "response",
            "task",
            "chronicle"
        ]
        return usageHints.contains { path.contains($0) }
    }

    func parse(_ url: URL) throws -> [UsageEvent] {
        let fileDate = fileTimestamp(url)
        var eventsByID: [String: UsageEvent] = [:]

        if url.pathExtension.lowercased() == "json" {
            let data = try Data(contentsOf: url)
            let root = try JSONSerialization.jsonObject(with: data)
            collectEvents(
                from: root,
                context: GenericUsageContext(timestamp: fileDate, provider: provider, model: modelFallback),
                url: url,
                breadcrumb: "root",
                eventsByID: &eventsByID
            )
        } else {
            try JSONLineReader.forEachObject(at: url) { object, lineNumber in
                collectEvents(
                    from: object,
                    context: GenericUsageContext(timestamp: fileDate, provider: provider, model: modelFallback),
                    url: url,
                    breadcrumb: "line-\(lineNumber)",
                    eventsByID: &eventsByID
                )
            }
        }

        return Array(eventsByID.values)
    }

    private func collectEvents(
        from value: Any,
        context: GenericUsageContext,
        url: URL,
        breadcrumb: String,
        depth: Int = 0,
        eventsByID: inout [String: UsageEvent]
    ) {
        guard depth <= 7 else { return }

        if let array = value as? [Any] {
            for (index, item) in array.enumerated() {
                collectEvents(
                    from: item,
                    context: context,
                    url: url,
                    breadcrumb: "\(breadcrumb).\(index)",
                    depth: depth + 1,
                    eventsByID: &eventsByID
                )
            }
            return
        }

        guard let object = value as? [String: Any] else { return }
        let localContext = context.merging(object: object)

        for key in GenericUsageNormalizer.usageKeys {
            guard let usage = object.dictionary(key),
                  let tokens = GenericUsageNormalizer.tokens(from: usage),
                  tokens.total > 0 else {
                continue
            }

            let eventID = genericEventID(
                object: object,
                url: url,
                breadcrumb: "\(breadcrumb).\(key)"
            )
            let event = UsageEvent(
                id: eventID,
                timestamp: localContext.timestamp,
                source: source,
                provider: usage.string("provider") ?? localContext.provider,
                model: usage.string("model") ?? usage.string("modelID") ?? localContext.model,
                tokens: tokens,
                costUSD: usage.double("cost") ?? usage.double("totalCost") ?? object.double("cost")
            )
            insertLargest(event, into: &eventsByID)
        }

        if GenericUsageNormalizer.looksLikeUsageObject(object),
           let tokens = GenericUsageNormalizer.tokens(from: object),
           tokens.total > 0 {
            let event = UsageEvent(
                id: genericEventID(object: object, url: url, breadcrumb: breadcrumb),
                timestamp: localContext.timestamp,
                source: source,
                provider: localContext.provider,
                model: localContext.model,
                tokens: tokens,
                costUSD: object.double("cost") ?? object.double("totalCost")
            )
            insertLargest(event, into: &eventsByID)
        }

        for (key, child) in object where !GenericUsageNormalizer.usageKeys.contains(key) {
            collectEvents(
                from: child,
                context: localContext,
                url: url,
                breadcrumb: "\(breadcrumb).\(key)",
                depth: depth + 1,
                eventsByID: &eventsByID
            )
        }
    }

    private func genericEventID(object: [String: Any], url: URL, breadcrumb: String) -> String {
        let stableID = object.string("id")
            ?? object.string("messageId")
            ?? object.string("messageID")
            ?? object.string("requestId")
            ?? object.string("requestID")
            ?? object.string("turnId")
            ?? object.string("turnID")
            ?? object.string("uuid")
            ?? breadcrumb
        return "\(source.id):\(url.path):\(stableID)"
    }

    private func insertLargest(_ event: UsageEvent, into eventsByID: inout [String: UsageEvent]) {
        if let existing = eventsByID[event.id], existing.tokens.total > event.tokens.total {
            return
        }
        eventsByID[event.id] = event
    }

    private func fileTimestamp(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
    }
}

private struct GenericUsageContext {
    let timestamp: Date
    let provider: String
    let model: String

    func merging(object: [String: Any]) -> GenericUsageContext {
        GenericUsageContext(
            timestamp: GenericUsageNormalizer.timestamp(from: object) ?? timestamp,
            provider: object.string("provider")
                ?? object.string("providerID")
                ?? object.string("providerId")
                ?? provider,
            model: object.string("model")
                ?? object.string("modelID")
                ?? object.string("modelId")
                ?? object.string("modelName")
                ?? model
        )
    }
}

private enum GenericUsageNormalizer {
    static let usageKeys: Set<String> = [
        "usage",
        "tokenUsage",
        "token_usage",
        "tokens",
        "usageMetadata",
        "metrics"
    ]

    static func tokens(from usage: [String: Any]) -> TokenBreakdown? {
        let cache = usage.dictionary("cache") ?? usage.dictionary("cacheTokens") ?? [:]
        let cacheRead = firstInt64(
            in: usage,
            keys: [
                "cacheRead",
                "cache_read",
                "cacheReadTokens",
                "cache_read_tokens",
                "cachedTokens",
                "cached_tokens",
                "cachedInputTokens",
                "cached_input_tokens",
                "cache_read_input_tokens",
                "inputCacheRead",
                "totalCacheReadTokens",
                "cacheReads"
            ]
        ) + firstInt64(in: cache, keys: ["read", "readTokens", "input"])
        let cacheWrite = firstInt64(
            in: usage,
            keys: [
                "cacheWrite",
                "cache_write",
                "cacheWriteTokens",
                "cache_write_tokens",
                "cacheCreationTokens",
                "cache_creation_tokens",
                "cache_creation_input_tokens",
                "inputCacheCreation",
                "totalCacheWriteTokens",
                "cacheWrites"
            ]
        ) + firstInt64(in: cache, keys: ["write", "writeTokens"])
        let reasoning = firstInt64(
            in: usage,
            keys: [
                "reasoning",
                "reasoningTokens",
                "reasoning_tokens",
                "reasoningOutputTokens",
                "reasoning_output_tokens",
                "thoughts",
                "thinking"
            ]
        )
        let rawInput = firstInt64(
            in: usage,
            keys: [
                "input",
                "inputTokens",
                "input_tokens",
                "promptTokens",
                "prompt_tokens",
                "tokensIn",
                "tokens_in",
                "totalInputTokens",
                "total_input_tokens",
                "inputOther"
            ]
        )
        let output = firstInt64(
            in: usage,
            keys: [
                "output",
                "outputTokens",
                "output_tokens",
                "completionTokens",
                "completion_tokens",
                "tokensOut",
                "tokens_out",
                "totalOutputTokens",
                "total_output_tokens",
                "responseTokens",
                "response_tokens"
            ]
        )
        let tokens = TokenBreakdown(
            input: rawInput,
            output: output + reasoning,
            cacheRead: cacheRead,
            cacheWrite: cacheWrite,
            reasoning: reasoning
        )

        guard rawInput > 0 || output > 0 || cacheRead > 0 || cacheWrite > 0 || reasoning > 0 else {
            return nil
        }
        return tokens
    }

    static func looksLikeUsageObject(_ object: [String: Any]) -> Bool {
        let keys = Set(object.keys)
        let tokenKeys: Set<String> = [
            "input",
            "inputTokens",
            "input_tokens",
            "promptTokens",
            "prompt_tokens",
            "output",
            "outputTokens",
            "output_tokens",
            "completionTokens",
            "completion_tokens",
            "tokensIn",
            "tokensOut",
            "cacheRead",
            "cacheWrite"
        ]
        return !keys.isDisjoint(with: tokenKeys)
    }

    static func timestamp(from object: [String: Any]) -> Date? {
        let keys = [
            "timestamp",
            "time",
            "created",
            "createdAt",
            "created_at",
            "completed",
            "completedAt",
            "completed_at",
            "updatedAt",
            "updated_at",
            "date",
            "startTime",
            "endTime",
            "ts"
        ]
        for key in keys {
            if let date = LogDateParser.parse(object[key]) {
                return date
            }
        }

        if let time = object.dictionary("time") {
            return LogDateParser.parse(time["completed"])
                ?? LogDateParser.parse(time["created"])
                ?? LogDateParser.parse(time["updated"])
        }
        return nil
    }

    private static func firstInt64(in object: [String: Any], keys: [String]) -> Int64 {
        for key in keys {
            let value = object.int64(key)
            if value > 0 { return value }
        }
        return 0
    }
}
