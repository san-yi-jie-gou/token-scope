import Foundation
import Network
import OSLog

enum WidgetSnapshotClient {
    private static let cachedSnapshotKey = "WidgetUsageSnapshot.lastValid"

    static func load(completion: @escaping (WidgetUsageSnapshot) -> Void) {
        let fallback = cachedSnapshot()
        WidgetSnapshotRequest(fallback: fallback) { snapshot in
            if snapshot.generatedAt != .distantPast,
               let data = try? JSONEncoder().encode(snapshot) {
                UserDefaults.standard.set(data, forKey: cachedSnapshotKey)
            }
            completion(snapshot)
        }
        .start()
    }

    private static func cachedSnapshot() -> WidgetUsageSnapshot {
        guard let data = UserDefaults.standard.data(forKey: cachedSnapshotKey),
              let snapshot = try? JSONDecoder().decode(WidgetUsageSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }
}

private final class WidgetSnapshotRequest {
    private static let logger = Logger(
        subsystem: "tech.qidao.app.tokenscope",
        category: "WidgetBridge"
    )

    private let queue = DispatchQueue(label: "tech.qidao.app.tokenscope.widget-client")
    private let fallback: WidgetUsageSnapshot
    private let completion: (WidgetUsageSnapshot) -> Void
    private var connection: NWConnection?
    private var keepAlive: WidgetSnapshotRequest?
    private var receivedData = Data()
    private var isFinished = false

    init(fallback: WidgetUsageSnapshot, completion: @escaping (WidgetUsageSnapshot) -> Void) {
        self.fallback = fallback
        self.completion = completion
    }

    func start() {
        keepAlive = self
        let port = NWEndpoint.Port(rawValue: WidgetBridge.port)!
        let connection = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.requestSnapshot()
            case .failed, .cancelled:
                self.finish(with: self.fallback)
            default:
                break
            }
        }

        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            self.finish(with: self.fallback)
        }
        connection.start(queue: queue)
    }

    private func requestSnapshot() {
        connection?.send(content: Data([1]), completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            guard error == nil else {
                self.finish(with: self.fallback)
                return
            }

            self.receiveSnapshot()
        })
    }

    private func receiveSnapshot() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data {
                self.receivedData.append(data)
            }
            guard error == nil, self.receivedData.count <= 1024 * 1024 else {
                self.finish(with: self.fallback)
                return
            }
            guard isComplete else {
                self.receiveSnapshot()
                return
            }

            let snapshot = (try? JSONDecoder().decode(WidgetUsageSnapshot.self, from: self.receivedData))
                .flatMap { $0.generatedAt == .distantPast ? nil : $0 }
                ?? self.fallback
            Self.logger.info("Widget received \(snapshot.displayedTokens, privacy: .public) tokens from localhost")
            self.finish(with: snapshot)
        }
    }

    private func finish(with snapshot: WidgetUsageSnapshot) {
        guard !isFinished else { return }
        isFinished = true
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        let completion = completion
        keepAlive = nil
        completion(snapshot)
    }
}
