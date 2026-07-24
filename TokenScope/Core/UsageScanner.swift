import Foundation

protocol UsageScanning {
    func scan(since startDate: Date) -> ScanResult
}

final class UsageScanner {
    private struct FileStamp: Equatable {
        let size: Int64
        let modifiedAt: Date
    }

    private struct CachedFile {
        let stamp: FileStamp
        let events: [UsageEvent]
    }

    private struct SourceScanResult {
        let events: [UsageEvent]
        let status: SourceStatus
        let cacheUpdates: [String: CachedFile]
    }

    private let parsers: [any UsageLogParser]
    private var cache: [String: CachedFile] = [:]
    private let fileManager: FileManager
    private let maximumConcurrentSources: Int
    private let scanLock = NSLock()

    convenience init(
        homeDirectory: URL,
        fileManager: FileManager = .default,
        maximumConcurrentSources: Int = 3
    ) {
        self.init(
            parsers: [
                CodexUsageParser(rootURL: homeDirectory.appendingPathComponent(".codex/sessions")),
                ClaudeUsageParser(rootURL: homeDirectory.appendingPathComponent(".claude/projects")),
                KimiUsageParser(rootURL: homeDirectory.appendingPathComponent(".kimi-code/sessions")),
                OMPUsageParser(rootURL: homeDirectory.appendingPathComponent(".pi/agent/sessions")),
                OpenCodeUsageParser(rootURL: homeDirectory.appendingPathComponent(".local/share/opencode/storage")),
                GeminiUsageParser(rootURL: homeDirectory.appendingPathComponent(".gemini/tmp")),
                GenericUsageLogParser(
                    source: .copilot,
                    rootURL: homeDirectory.appendingPathComponent(".copilot"),
                    provider: "GitHub",
                    modelFallback: "GitHub Copilot"
                ),
                GenericUsageLogParser(
                    source: .copilot,
                    rootURL: homeDirectory.appendingPathComponent("Library/Application Support/Code/User/globalStorage/github.copilot-chat"),
                    provider: "GitHub",
                    modelFallback: "GitHub Copilot"
                ),
                GenericUsageLogParser(
                    source: .cursor,
                    rootURL: homeDirectory.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage"),
                    provider: "Cursor",
                    modelFallback: "Cursor"
                ),
                GenericUsageLogParser(
                    source: .qoder,
                    rootURL: homeDirectory.appendingPathComponent(".qoder"),
                    provider: "Qoder",
                    modelFallback: "Qoder"
                ),
                GenericUsageLogParser(
                    source: .qoder,
                    rootURL: homeDirectory.appendingPathComponent("Library/Application Support/Qoder/User/globalStorage"),
                    provider: "Qoder",
                    modelFallback: "Qoder"
                ),
                GenericUsageLogParser(
                    source: .windsurf,
                    rootURL: homeDirectory.appendingPathComponent("Library/Application Support/Windsurf/User/globalStorage"),
                    provider: "Windsurf",
                    modelFallback: "Windsurf"
                ),
                GenericUsageLogParser(
                    source: .cline,
                    rootURL: homeDirectory.appendingPathComponent("Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev"),
                    provider: "Cline",
                    modelFallback: "Cline"
                ),
                GenericUsageLogParser(
                    source: .trae,
                    rootURL: homeDirectory.appendingPathComponent("Library/Application Support/Trae/User/globalStorage"),
                    provider: "Trae",
                    modelFallback: "Trae"
                )
            ],
            fileManager: fileManager,
            maximumConcurrentSources: maximumConcurrentSources
        )
    }

    init(
        parsers: [any UsageLogParser],
        fileManager: FileManager = .default,
        maximumConcurrentSources: Int = 3
    ) {
        self.parsers = parsers
        self.fileManager = fileManager
        self.maximumConcurrentSources = max(1, maximumConcurrentSources)
    }

    func scan(since startDate: Date) -> ScanResult {
        scan(since: startDate, now: Date())
    }

    func scan(since startDate: Date, now: Date) -> ScanResult {
        scanLock.lock()
        defer { scanLock.unlock() }

        let cachedFiles = cache
        let queue = OperationQueue()
        queue.name = "tech.qidao.app.tokenscope.source-scan"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = max(1, min(maximumConcurrentSources, parsers.count))
        let resultLock = NSLock()
        var sourceResults: [SourceScanResult] = []

        for parser in parsers {
            queue.addOperation { [fileManager] in
                let result = Self.scanSource(
                    parser,
                    since: startDate,
                    now: now,
                    fileManager: fileManager,
                    cachedFiles: cachedFiles
                )
                resultLock.lock()
                sourceResults.append(result)
                resultLock.unlock()
            }
        }
        queue.waitUntilAllOperationsAreFinished()

        var allEvents: [UsageEvent] = []
        var statuses: [UsageSource: SourceStatus] = [:]
        for result in sourceResults {
            cache.merge(result.cacheUpdates) { _, update in update }
            allEvents.append(contentsOf: result.events)
            statuses[result.status.source] = Self.merge(statuses[result.status.source], with: result.status)
        }

        return ScanResult(
            events: allEvents.sorted { $0.timestamp < $1.timestamp },
            statuses: statuses,
            scannedAt: now
        )
    }

    private static func scanSource(
        _ parser: any UsageLogParser,
        since startDate: Date,
        now: Date,
        fileManager: FileManager,
        cachedFiles: [String: CachedFile]
    ) -> SourceScanResult {
        var isDirectory: ObjCBool = false
        let available = fileManager.fileExists(atPath: parser.rootURL.path, isDirectory: &isDirectory)
            && isDirectory.boolValue

        guard available else {
            return SourceScanResult(
                events: [],
                status: SourceStatus(
                    source: parser.source,
                    isAvailable: false,
                    fileCount: 0,
                    eventCount: 0,
                    errorCount: 0
                ),
                cacheUpdates: [:]
            )
        }

        var sourceEvents: [UsageEvent] = []
        var cacheUpdates: [String: CachedFile] = [:]
        var fileCount = 0
        var errorCount = 0
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        let enumerator = fileManager.enumerator(
            at: parser.rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants, .skipsHiddenFiles]
        )

        while let url = enumerator?.nextObject() as? URL {
            guard parser.accepts(url) else { continue }
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt >= startDate.addingTimeInterval(-24 * 60 * 60) else {
                continue
            }

            fileCount += 1
            let stamp = FileStamp(size: Int64(values.fileSize ?? 0), modifiedAt: modifiedAt)
            let cacheKey = "\(parser.source.id):\(url.path)"

            if let cached = cachedFiles[cacheKey], cached.stamp == stamp {
                sourceEvents.append(contentsOf: cached.events)
                continue
            }

            do {
                let events = try parser.parse(url)
                cacheUpdates[cacheKey] = CachedFile(stamp: stamp, events: events)
                sourceEvents.append(contentsOf: events)
            } catch {
                errorCount += 1
            }
        }

        let filtered = sourceEvents.filter {
            $0.timestamp >= startDate && $0.timestamp <= now.addingTimeInterval(5 * 60)
        }
        return SourceScanResult(
            events: filtered,
            status: SourceStatus(
                source: parser.source,
                isAvailable: true,
                fileCount: fileCount,
                eventCount: filtered.count,
                errorCount: errorCount
            ),
            cacheUpdates: cacheUpdates
        )
    }

    private static func merge(_ existing: SourceStatus?, with update: SourceStatus) -> SourceStatus {
        guard let existing else { return update }
        return SourceStatus(
            source: update.source,
            isAvailable: existing.isAvailable || update.isAvailable,
            fileCount: existing.fileCount + update.fileCount,
            eventCount: existing.eventCount + update.eventCount,
            errorCount: existing.errorCount + update.errorCount
        )
    }
}

extension UsageScanner: UsageScanning {}
