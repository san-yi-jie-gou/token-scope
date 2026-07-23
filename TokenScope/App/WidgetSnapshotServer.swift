import Foundation
import Network
import OSLog

final class WidgetSnapshotServer {
    static let shared = WidgetSnapshotServer()

    private static let logger = Logger(
        subsystem: "tech.qidao.app.tokenscope",
        category: "WidgetBridge"
    )

    private let queue = DispatchQueue(label: "tech.qidao.app.tokenscope.widget-server")
    private let lock = NSLock()
    private var listener: NWListener?
    private var snapshot = WidgetUsageSnapshot.empty

    private init() {}

    func start() {
        queue.async { [weak self] in
            guard let self, self.listener == nil else { return }

            do {
                let parameters = NWParameters.tcp
                let port = NWEndpoint.Port(rawValue: WidgetBridge.port)!
                parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)

                let listener = try NWListener(using: parameters)
                listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection)
                }
                listener.stateUpdateHandler = { state in
                    if case .ready = state {
                        Self.logger.info("Widget bridge is listening on localhost")
                    } else if case .failed(let error) = state {
                        Self.logger.error("Widget bridge failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
                self.listener = listener
                listener.start(queue: self.queue)
            } catch {
                Self.logger.error("Unable to start widget bridge: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @discardableResult
    func update(_ snapshot: WidgetUsageSnapshot) -> Bool {
        lock.lock()
        let displayContentChanged = !self.snapshot.hasSameDisplayContent(as: snapshot)
            || self.snapshot.generatedAt == .distantPast
        self.snapshot = snapshot
        lock.unlock()
        Self.logger.info("Widget bridge updated: \(snapshot.displayedTokens, privacy: .public) tokens")
        return displayContentChanged
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16) { [weak self] _, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }

            self.lock.lock()
            let snapshot = self.snapshot
            self.lock.unlock()
            let data = try? JSONEncoder().encode(snapshot)

            connection.send(content: data, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}
