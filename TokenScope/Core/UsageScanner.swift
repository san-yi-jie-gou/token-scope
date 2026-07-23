import Foundation

final class UsageScanner {
    private struct FileStamp: Equatable {
        let size: Int64
        let modifiedAt: Date
    }

    private struct CachedFile {
        let stamp: FileStamp
        let events: [UsageEvent]
    }

    private let parsers: [any UsageLogParser]
    private var cache: [String: CachedFile] = [:]
    private let fileManager: FileManager

    init(homeDirectory: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.parsers = [
            CodexUsageParser(rootURL: homeDirectory.appendingPathComponent(".codex/sessions")),
            ClaudeUsageParser(rootURL: homeDirectory.appendingPathComponent(".claude/projects")),
            KimiUsageParser(rootURL: homeDirectory.appendingPathComponent(".kimi-code/sessions")),
            OMPUsageParser(rootURL: homeDirectory.appendingPathComponent(".pi/agent/sessions")),
            OpenCodeUsageParser(rootURL: homeDirectory.appendingPathComponent(".local/share/opencode/storage/session")),
            GeminiUsageParser(rootURL: homeDirectory.appendingPathComponent(".gemini/tmp"))
        ]
    }

    func scan(since startDate: Date, now: Date = Date()) -> ScanResult {
        var allEvents: [UsageEvent] = []
        var statuses: [UsageSource: SourceStatus] = [:]

        for parser in parsers {
            var isDirectory: ObjCBool = false
            let available = fileManager.fileExists(atPath: parser.rootURL.path, isDirectory: &isDirectory)
                && isDirectory.boolValue

            guard available else {
                statuses[parser.source] = SourceStatus(
                    source: parser.source,
                    isAvailable: false,
                    fileCount: 0,
                    eventCount: 0,
                    errorCount: 0
                )
                continue
            }

            var sourceEvents: [UsageEvent] = []
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

                if let cached = cache[cacheKey], cached.stamp == stamp {
                    sourceEvents.append(contentsOf: cached.events)
                    continue
                }

                do {
                    let events = try parser.parse(url)
                    cache[cacheKey] = CachedFile(stamp: stamp, events: events)
                    sourceEvents.append(contentsOf: events)
                } catch {
                    errorCount += 1
                }
            }

            let filtered = sourceEvents.filter {
                $0.timestamp >= startDate && $0.timestamp <= now.addingTimeInterval(5 * 60)
            }
            allEvents.append(contentsOf: filtered)
            statuses[parser.source] = SourceStatus(
                source: parser.source,
                isAvailable: true,
                fileCount: fileCount,
                eventCount: filtered.count,
                errorCount: errorCount
            )
        }

        return ScanResult(
            events: allEvents.sorted { $0.timestamp < $1.timestamp },
            statuses: statuses,
            scannedAt: now
        )
    }
}
