import Foundation
import Network
import Testing
@testable import ThreadHaven

@Suite(.serialized)
struct HTTPServerTests {
    private func startServer(_ handler: @escaping (HTTPRequest, HTTPConnection) -> Void) async throws -> (HTTPServer, UInt16) {
        let server = HTTPServer()
        server.onRequest = handler
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let resumed = Locked(false)
            server.start(port: 0) { result in
                guard resumed.swap(true) == false else { return }
                continuation.resume(with: result)
            }
        }
        return (server, port)
    }

    private func exchange(port: UInt16, _ text: String) async throws -> String {
        let connection = NWConnection(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let queue = DispatchQueue(label: "test-client")
        connection.start(queue: queue)
        defer { connection.cancel() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: Data(text.utf8), completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
        var received = Data()
        while true {
            let (data, done): (Data?, Bool) = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: (data, isComplete)) }
                }
            }
            if let data { received.append(data) }
            if done || received.count > 1_000_000 { break }
        }
        return String(decoding: received, as: UTF8.self)
    }

    @Test func answersOverLoopback() async throws {
        let (server, port) = try await startServer { request, connection in
            connection.respond(.json(["path": request.path, "body": String(decoding: request.body, as: UTF8.self)]))
        }
        defer { server.stop() }
        #expect(port > 0)
        let reply = try await exchange(port: port, "POST /echo HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhello")
        #expect(reply.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(reply.contains("Content-Security-Policy:"))
        #expect(reply.hasSuffix(#"{"body":"hello","path":"\/echo"}"#) || reply.hasSuffix(#"{"body":"hello","path":"/echo"}"#))
    }

    @Test func servesPipelinedRequestsOnOneConnection() async throws {
        let (server, port) = try await startServer { request, connection in
            connection.respond(.json(["path": request.path]))
        }
        defer { server.stop() }
        let reply = try await exchange(port: port, "GET /one HTTP/1.1\r\nHost: a\r\n\r\nGET /two HTTP/1.1\r\nHost: a\r\nConnection: close\r\n\r\n")
        #expect(reply.components(separatedBy: "HTTP/1.1 200 OK").count == 3)
        #expect(reply.contains("one") && reply.contains("two"))
    }

    @Test func rejectsMalformedRequestsAndCloses() async throws {
        let (server, port) = try await startServer { _, connection in
            connection.respond(.json([:]))
        }
        defer { server.stop() }
        let reply = try await exchange(port: port, "GET / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n")
        #expect(reply.hasPrefix("HTTP/1.1 501 Not Implemented\r\n"))
        #expect(reply.contains("Connection: close"))
        let garbage = try await exchange(port: port, "\u{16}\u{3}\u{1}garbage\r\n\r\n")
        #expect(garbage.hasPrefix("HTTP/1.1 400 Bad Request\r\n"))
    }

    @Test func closesEventStreamsAfterTheirLifetime() async throws {
        let (server, port) = try await startServer { _, connection in
            DispatchQueue.global().async {
                _ = connection.beginEventStream(initial: Data("event: sessions\ndata: {}\n\n".utf8), lifetime: 0.3) {}
            }
        }
        defer { server.stop() }
        let started = Date()
        let reply = try await exchange(port: port, "GET /api/events HTTP/1.1\r\nHost: a\r\n\r\n")
        #expect(reply.contains("event: sessions"))
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test func streamsServerSentEvents() async throws {
        let (server, port) = try await startServer { _, connection in
            DispatchQueue.global().async {
                _ = connection.beginEventStream(initial: Data("event: sessions\ndata: {}\n\n".utf8)) {}
                connection.sendEvent(Data(": ping\n\n".utf8))
                connection.close()
            }
        }
        defer { server.stop() }
        let reply = try await exchange(port: port, "GET /api/events HTTP/1.1\r\nHost: a\r\n\r\n")
        #expect(reply.contains("Content-Type: text/event-stream"))
        #expect(reply.contains("event: sessions\ndata: {}\n\n"))
    }
}

final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) { self.value = value }

    func swap(_ newValue: Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        let old = value
        value = newValue
        return old
    }
}
