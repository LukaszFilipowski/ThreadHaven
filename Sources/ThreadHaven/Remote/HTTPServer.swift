import Foundation
import Network

final class HTTPServer: @unchecked Sendable {
    static let maxConnections = 32
    static let maxEventStreams = 8
    static let requestTimeout: TimeInterval = 10
    static let idleTimeout: TimeInterval = 30
    static let maxRequestsPerConnection = 200
    static let eventStreamLifetime: TimeInterval = 900

    let queue = DispatchQueue(label: "app.threadhaven.remote-server")
    var onRequest: ((HTTPRequest, HTTPConnection) -> Void)?

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: HTTPConnection] = [:]

    func start(port: UInt16, onState: @escaping @Sendable (Result<UInt16, Error>) -> Void) {
        queue.async { [self] in
            stopLocked()
            do {
                let parameters = NWParameters.tcp
                parameters.acceptLocalOnly = true
                parameters.allowLocalEndpointReuse = true
                parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port) ?? .any)
                let listener = try NWListener(using: parameters)
                listener.newConnectionHandler = { [weak self] connection in
                    self?.accept(connection)
                }
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    switch state {
                    case .ready:
                        onState(.success(listener?.port?.rawValue ?? port))
                    case .failed(let error), .waiting(let error):
                        self?.stopLocked()
                        onState(.failure(error))
                    default:
                        break
                    }
                }
                self.listener = listener
                listener.start(queue: queue)
            } catch {
                onState(.failure(error))
            }
        }
    }

    func stop() {
        queue.async { [self] in stopLocked() }
    }

    var eventStreamCount: Int {
        connections.values.filter(\.isEventStream).count
    }

    private func stopLocked() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.close() }
        connections.removeAll()
    }

    private func accept(_ nwConnection: NWConnection) {
        guard connections.count < Self.maxConnections, isLoopback(nwConnection.endpoint) else {
            nwConnection.cancel()
            return
        }
        let connection = HTTPConnection(connection: nwConnection, server: self)
        connections[ObjectIdentifier(connection)] = connection
        connection.start()
    }

    private func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address): return address == .loopback
        case .ipv6(let address): return address == .loopback
        default: return false
        }
    }

    fileprivate func remove(_ connection: HTTPConnection) {
        connections[ObjectIdentifier(connection)] = nil
    }

    fileprivate func dispatch(_ request: HTTPRequest, from connection: HTTPConnection) {
        guard let onRequest else {
            connection.respond(.error(503, "Unavailable"))
            return
        }
        onRequest(request, connection)
    }
}

final class HTTPConnection: @unchecked Sendable {
    private let connection: NWConnection
    private weak var server: HTTPServer?
    private let queue: DispatchQueue
    private var buffer = Data()
    private var busy = false
    private var closed = false
    private var handled = 0
    private var timer: DispatchSourceTimer?
    private var keepAlive = true
    private var headOnly = false
    private(set) var isEventStream = false
    private var onClose: (@Sendable () -> Void)?

    init(connection: NWConnection, server: HTTPServer) {
        self.connection = connection
        self.server = server
        self.queue = server.queue
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.close()
            default:
                break
            }
        }
        connection.start(queue: queue)
        arm(HTTPServer.requestTimeout)
        receive()
    }

    func respond(_ response: HTTPResponse) {
        queue.async { [self] in
            guard !closed, busy, !isEventStream else { return }
            let reuse = keepAlive && handled < HTTPServer.maxRequestsPerConnection && response.status < 400
            let data = response.serialized(keepAlive: reuse, includeBody: !headOnly)
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if error != nil || !reuse {
                    self.close()
                    return
                }
                self.busy = false
                self.arm(self.buffer.isEmpty ? HTTPServer.idleTimeout : HTTPServer.requestTimeout)
                self.process()
            })
        }
    }

    func beginEventStream(initial: Data, lifetime: TimeInterval = HTTPServer.eventStreamLifetime, onClose: @escaping @Sendable () -> Void) -> Bool {
        dispatchPrecondition(condition: .notOnQueue(queue))
        return queue.sync {
            guard !closed, busy, !isEventStream,
                  (server?.eventStreamCount ?? HTTPServer.maxEventStreams) < HTTPServer.maxEventStreams else { return false }
            isEventStream = true
            self.onClose = onClose
            timer?.cancel()
            let limit = DispatchSource.makeTimerSource(queue: queue)
            limit.schedule(deadline: .now() + lifetime)
            limit.setEventHandler { [weak self] in self?.closeLocked() }
            limit.resume()
            timer = limit
            var data = HTTPResponse.eventStreamHead()
            data.append(initial)
            write(data)
            return true
        }
    }

    func sendEvent(_ data: Data) {
        queue.async { [self] in
            guard !closed, isEventStream else { return }
            write(data)
        }
    }

    func close() {
        queue.async { [self] in closeLocked() }
    }

    private func closeLocked() {
        guard !closed else { return }
        closed = true
        timer?.cancel()
        timer = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        server?.remove(self)
        let onClose = onClose
        self.onClose = nil
        onClose?()
    }

    private func write(_ data: Data) {
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if error != nil { self?.closeLocked() }
        })
    }

    private func arm(_ interval: TimeInterval) {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler { [weak self] in
            guard let self, !self.busy else { return }
            self.closeLocked()
        }
        timer.resume()
        self.timer = timer
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self, !self.closed else { return }
            if let data, !data.isEmpty {
                if self.isEventStream {
                    self.receive()
                    return
                }
                let wasEmpty = self.buffer.isEmpty
                self.buffer.append(data)
                if self.buffer.count > HTTPParser.maxHeaderBytes + HTTPParser.maxBodyBytes + 8 {
                    self.fail(413)
                    return
                }
                if !self.busy && wasEmpty { self.arm(HTTPServer.requestTimeout) }
                self.process()
            }
            if isComplete || error != nil {
                if !self.busy { self.closeLocked() }
                return
            }
            self.receive()
        }
    }

    private func process() {
        guard !busy, !closed, !isEventStream, !buffer.isEmpty else { return }
        switch HTTPParser.parse(buffer) {
        case .incomplete:
            return
        case .failure(let status):
            fail(status)
        case .complete(let request, let consumed):
            buffer.removeFirst(consumed)
            buffer = Data(buffer)
            busy = true
            handled += 1
            keepAlive = request.keepAlive
            headOnly = request.method == "HEAD"
            timer?.cancel()
            timer = nil
            server?.dispatch(request, from: self)
        }
    }

    private func fail(_ status: Int) {
        busy = true
        keepAlive = false
        let data = HTTPResponse.error(status, HTTPResponse.reason(status)).serialized(keepAlive: false)
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in
            self?.closeLocked()
        })
    }
}
