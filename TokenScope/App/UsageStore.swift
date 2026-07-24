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
            defaults.set(includesCache, forKey: Self.includesCacheKey)
            rebuildAggregates()
            publishWidgetSnapshot()
            notifyActiveSourceCount()
        }
    }
    @Published var range: UsageRange {
        didSet {
            defaults.set(range.rawValue, forKey: Self.rangeKey)
            let referenceDate = lastUpdated ?? dateProvider()
            rebuildAggregates(referenceDate: referenceDate)
            publishWidgetSnapshot()
            notifyActiveSourceCount()
            refreshIfSelectedRangeNeedsMoreData(referenceDate: referenceDate)
        }
    }

    var onLayoutChange: ((Int, UsageRange) -> Void)?
    var onRequestDataDirectoryAccess: (() -> Void)?

    private static let rangeKey = "usageRange"
    private static let includesCacheKey = "includesCache"
    private var scanner: (any UsageScanning)?
    private let dataDirectoryAccess: DataDirectoryAccess
    private let defaults: UserDefaults
    private let snapshotPublisher: ([UsageEvent], Bool, UsageRange, Date, Date?) -> Void
    private let dateProvider: () -> Date
    private let workQueue = DispatchQueue(label: "tech.qidao.app.tokenscope.scan", qos: .utility)

    init(
        scanner: (any UsageScanning)? = nil,
        dataDirectoryAccess: DataDirectoryAccess = DataDirectoryAccess(),
        defaults: UserDefaults = .standard,
        snapshotPublisher: @escaping ([UsageEvent], Bool, UsageRange, Date, Date?) -> Void = {
            events,
            includesCache,
            range,
            generatedAt,
            referenceDate in
            WidgetSnapshotPublisher.publish(
                events: events,
                includesCache: includesCache,
                range: range,
                generatedAt: generatedAt,
                referenceDate: referenceDate
            )
        },
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.dataDirectoryAccess = dataDirectoryAccess
        self.defaults = defaults
        self.snapshotPublisher = snapshotPublisher
        self.dateProvider = dateProvider
        if let scanner {
            self.scanner = scanner
            self.hasDataDirectoryAccess = true
        } else if let homeDirectory = dataDirectoryAccess.restore() {
            self.scanner = UsageScanner(homeDirectory: homeDirectory)
            self.hasDataDirectoryAccess = true
        }
        let stored = defaults.string(forKey: Self.rangeKey)
        self.range = UsageRange(rawValue: stored ?? "") ?? .today
        self.includesCache = defaults.bool(forKey: Self.includesCacheKey)
    }

    private var isScanning = false
    private var loadedStartDate: Date?

    func refresh(userInitiated _: Bool = false) {
        guard let scanner else { return }
        guard !isScanning else { return }

        let foregroundStart = range.startDate(relativeTo: dateProvider())
        let shouldBackfillMonth = range == .today
        startScan(
            using: scanner,
            since: foregroundStart,
            isUserVisible: true,
            backfillMonthAfter: shouldBackfillMonth
        )
    }

    private func startScan(
        using scanner: any UsageScanning,
        since startDate: Date,
        isUserVisible: Bool,
        backfillMonthAfter: Bool
    ) {
        guard !isScanning else { return }
        if isUserVisible {
            isRefreshing = true
        }
        isScanning = true

        workQueue.async { [weak self] in
            let result = scanner.scan(since: startDate)
            DispatchQueue.main.async {
                guard let self else { return }
                self.applyScanResult(result, loadedStartDate: startDate)
                self.isScanning = false
                if isUserVisible {
                    self.isRefreshing = false
                }
                if backfillMonthAfter {
                    self.backfillMonthIfNeeded()
                }
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
        loadedStartDate = nil
        refresh()
    }

    private func applyScanResult(_ result: ScanResult, loadedStartDate: Date) {
        events = result.events
        statuses = result.statuses
        lastUpdated = result.scannedAt
        self.loadedStartDate = loadedStartDate
        rebuildAggregates(referenceDate: result.scannedAt)
        snapshotPublisher(
            result.events,
            includesCache,
            range,
            result.scannedAt,
            nil
        )
        notifyActiveSourceCount()
    }

    private func backfillMonthIfNeeded() {
        guard let scanner, !isScanning else { return }
        let monthStart = UsageRange.month.startDate(relativeTo: dateProvider())
        guard loadedStartDate.map({ $0 > monthStart }) ?? true else { return }
        startScan(
            using: scanner,
            since: monthStart,
            isUserVisible: false,
            backfillMonthAfter: false
        )
    }

    private func refreshIfSelectedRangeNeedsMoreData(referenceDate: Date) {
        guard hasDataDirectoryAccess,
              !isScanning,
              let scanner else {
            return
        }

        let requiredStart = range.startDate(relativeTo: referenceDate)
        guard loadedStartDate.map({ $0 > requiredStart }) ?? true else { return }
        startScan(
            using: scanner,
            since: requiredStart,
            isUserVisible: true,
            backfillMonthAfter: range == .today
        )
    }

    private func notifyActiveSourceCount() {
        onLayoutChange?(summary.sources.count, range)
    }

    private func publishWidgetSnapshot() {
        snapshotPublisher(
            events,
            includesCache,
            range,
            lastUpdated ?? dateProvider(),
            dateProvider()
        )
    }

    private func rebuildAggregates(referenceDate: Date? = nil) {
        let referenceDate = referenceDate ?? dateProvider()
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
