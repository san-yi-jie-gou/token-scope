import Foundation

final class UsageStore: ObservableObject {
    @Published private(set) var events: [UsageEvent] = []
    @Published private(set) var statuses: [UsageSource: SourceStatus] = [:]
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var hasDataDirectoryAccess = false
    @Published private(set) var summary: UsageSummary = .empty
    @Published private(set) var dailyUsage: [DailyUsageSummary] = []
    @Published var includesCache: Bool {
        didSet {
            UserDefaults.standard.set(includesCache, forKey: Self.includesCacheKey)
            rebuildAggregates()
            publishWidgetSnapshot()
            notifyActiveSourceCount()
        }
    }
    @Published var range: UsageRange {
        didSet {
            UserDefaults.standard.set(range.rawValue, forKey: Self.rangeKey)
            rebuildAggregates()
            publishWidgetSnapshot()
            notifyActiveSourceCount()
        }
    }

    var onLayoutChange: ((Int, UsageRange) -> Void)?
    var onRequestDataDirectoryAccess: (() -> Void)?

    private static let rangeKey = "usageRange"
    private static let includesCacheKey = "includesCache"
    private var scanner: UsageScanner?
    private let dataDirectoryAccess: DataDirectoryAccess
    private let workQueue = DispatchQueue(label: "tech.qidao.app.tokenscope.scan", qos: .utility)

    init(scanner: UsageScanner? = nil, dataDirectoryAccess: DataDirectoryAccess = DataDirectoryAccess()) {
        self.dataDirectoryAccess = dataDirectoryAccess
        if let scanner {
            self.scanner = scanner
            self.hasDataDirectoryAccess = true
        } else if let homeDirectory = dataDirectoryAccess.restore() {
            self.scanner = UsageScanner(homeDirectory: homeDirectory)
            self.hasDataDirectoryAccess = true
        }
        let stored = UserDefaults.standard.string(forKey: Self.rangeKey)
        self.range = UsageRange(rawValue: stored ?? "") ?? .today
        self.includesCache = UserDefaults.standard.bool(forKey: Self.includesCacheKey)
    }

    private var isScanning = false

    func refresh(userInitiated: Bool = false) {
        guard let scanner else { return }
        if userInitiated {
            isRefreshing = true
        }
        guard !isScanning else { return }
        isScanning = true

        let start = UsageRange.month.startDate()
        workQueue.async { [weak self] in
            let result = scanner.scan(since: start)
            DispatchQueue.main.async {
                guard let self else { return }
                self.events = result.events
                self.statuses = result.statuses
                self.lastUpdated = result.scannedAt
                self.isScanning = false
                self.isRefreshing = false
                self.rebuildAggregates(referenceDate: result.scannedAt)
                WidgetSnapshotPublisher.publish(
                    events: result.events,
                    includesCache: self.includesCache,
                    range: self.range,
                    generatedAt: result.scannedAt
                )
                self.notifyActiveSourceCount()
            }
        }
    }

    func authorizeDataDirectory(_ url: URL) throws {
        let homeDirectory = try dataDirectoryAccess.authorize(url)
        scanner = UsageScanner(homeDirectory: homeDirectory)
        hasDataDirectoryAccess = true
        events = []
        statuses = [:]
        lastUpdated = nil
        summary = .empty
        dailyUsage = []
        refresh()
    }

    private func notifyActiveSourceCount() {
        onLayoutChange?(summary.sources.count, range)
    }

    private func publishWidgetSnapshot() {
        WidgetSnapshotPublisher.publish(
            events: events,
            includesCache: includesCache,
            range: range,
            generatedAt: lastUpdated ?? Date(),
            referenceDate: Date()
        )
    }

    private func rebuildAggregates(referenceDate: Date = Date()) {
        let displayedStart = range.startDate(relativeTo: referenceDate)
        summary = UsageSummary.make(
            from: events.filter { $0.timestamp >= displayedStart },
            includingCache: includesCache
        )

        let monthStart = UsageRange.month.startDate(relativeTo: referenceDate)
        dailyUsage = DailyUsageSummary.make(
            from: events.filter { $0.timestamp >= monthStart },
            includingCache: includesCache
        )
    }
}
