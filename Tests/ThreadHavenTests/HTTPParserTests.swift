import Foundation
import Testing
@testable import ThreadHaven

struct HTTPParserTests {
    private func parse(_ text: String) -> HTTPParseResult {
        HTTPParser.parse(Data(text.utf8))
    }

    private func request(_ text: String) throws -> (HTTPRequest, Int) {
        guard case .complete(let request, let consumed) = parse(text) else {
            Issue.record("Expected a complete request")
            throw CancellationError()
        }
        return (request, consumed)
    }

    @Test func parsesASimpleGet() throws {
        let text = "GET /api/sessions?x=1 HTTP/1.1\r\nHost: example.invalid\r\nAuthorization:  Bearer abc \r\n\r\n"
        let (request, consumed) = try request(text)
        #expect(request.method == "GET")
        #expect(request.target == "/api/sessions?x=1")
        #expect(request.path == "/api/sessions")
        #expect(request.header("HOST") == "example.invalid")
        #expect(request.header("authorization") == "Bearer abc")
        #expect(request.body.isEmpty)
        #expect(request.keepAlive)
        #expect(consumed == text.utf8.count)
    }

    @Test func waitsForMoreData() {
        #expect(parse("GET / HTTP/1.1\r\nHost: a\r\n") == .incomplete)
        #expect(parse("") == .incomplete)
        #expect(parse("POST /x HTTP/1.1\r\nHost: a\r\nContent-Length: 10\r\n\r\n12345") == .incomplete)
    }

    @Test func readsBodyByContentLengthAndLeavesPipelinedBytes() throws {
        let text = "POST /x HTTP/1.1\r\nHost: a\r\nContent-Length: 5\r\n\r\nhelloGET / HTTP/1.1\r\n"
        let (request, consumed) = try request(text)
        #expect(request.body == Data("hello".utf8))
        #expect(consumed == text.utf8.count - "GET / HTTP/1.1\r\n".utf8.count)
    }

    @Test func rejectsMalformedRequestLines() {
        #expect(parse("GET  / HTTP/1.1\r\nHost: a\r\n\r\n") == .failure(400))
        #expect(parse("GET / HTTP/1.1 extra\r\nHost: a\r\n\r\n") == .failure(400))
        #expect(parse("get / HTTP/1.1\r\nHost: a\r\n\r\n") == .failure(400))
        #expect(parse("GET http://evil.invalid/ HTTP/1.1\r\nHost: a\r\n\r\n") == .failure(400))
        #expect(parse("GET /a\u{7F} HTTP/1.1\r\nHost: a\r\n\r\n") == .failure(400))
        #expect(parse("GET / HTTP/2.0\r\nHost: a\r\n\r\n") == .failure(505))
        #expect(parse("\r\n\r\n") == .failure(400))
    }

    @Test func rejectsMalformedHeaders() {
        #expect(parse("GET / HTTP/1.1\r\nHost: a\r\nBad Header: x\r\n\r\n") == .failure(400))
        #expect(parse("GET / HTTP/1.1\r\nHost: a\r\n folded: x\r\n\r\n") == .failure(400))
        #expect(parse("GET / HTTP/1.1\r\nHost: a\r\n: x\r\n\r\n") == .failure(400))
        #expect(parse("GET / HTTP/1.1\r\nHost: a\r\nX: a\u{0}b\r\n\r\n") == .failure(400))
        #expect(parse("GET / HTTP/1.1\r\nHost: a\r\nX: a\nInjected: b\r\n\r\n") == .failure(400))
        #expect(parse("GET / HTTP/1.1\r\nNoColon\r\nHost: a\r\n\r\n") == .failure(400))
    }

    @Test func requiresExactlyOneHostOnHTTP11() {
        #expect(parse("GET / HTTP/1.1\r\n\r\n") == .failure(400))
        #expect(parse("GET / HTTP/1.1\r\nHost: a\r\nHost: b\r\n\r\n") == .failure(400))
        if case .complete = parse("GET / HTTP/1.0\r\n\r\n") {} else { Issue.record("HTTP/1.0 without Host should parse") }
    }

    @Test func validatesContentLength() {
        #expect(parse("POST / HTTP/1.1\r\nHost: a\r\nContent-Length: -1\r\n\r\n") == .failure(400))
        #expect(parse("POST / HTTP/1.1\r\nHost: a\r\nContent-Length: +5\r\n\r\n") == .failure(400))
        #expect(parse("POST / HTTP/1.1\r\nHost: a\r\nContent-Length: 1,1\r\n\r\n") == .failure(400))
        #expect(parse("POST / HTTP/1.1\r\nHost: a\r\nContent-Length:\r\n\r\n") == .failure(400))
        #expect(parse("POST / HTTP/1.1\r\nHost: a\r\nContent-Length: 99999999999999999999\r\n\r\n") == .failure(400))
        #expect(parse("POST / HTTP/1.1\r\nHost: a\r\nContent-Length: 2\r\nContent-Length: 2\r\n\r\nab") == .failure(400))
        #expect(parse("POST / HTTP/1.1\r\nHost: a\r\nContent-Length: \(HTTPParser.maxBodyBytes + 1)\r\n\r\n") == .failure(413))
    }

    @Test func rejectsTransferEncoding() {
        #expect(parse("POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n") == .failure(501))
        #expect(parse("POST / HTTP/1.1\r\nHost: a\r\nContent-Length: 3\r\nTransfer-Encoding: chunked\r\n\r\nabc") == .failure(501))
    }

    @Test func enforcesSizeLimits() {
        let longTarget = "/" + String(repeating: "a", count: HTTPParser.maxTargetLength)
        #expect(parse("GET \(longTarget) HTTP/1.1\r\nHost: a\r\n\r\n") == .failure(414))

        let hugeHeader = "GET / HTTP/1.1\r\nHost: a\r\nX: " + String(repeating: "a", count: HTTPParser.maxHeaderBytes)
        #expect(parse(hugeHeader) == .failure(431))

        let many = (0...HTTPParser.maxHeaderCount).map { "X-\($0): v\r\n" }.joined()
        #expect(parse("GET / HTTP/1.1\r\nHost: a\r\n\(many)\r\n") == .failure(431))
    }

    @Test func keepAliveFollowsVersionAndConnectionHeader() throws {
        #expect(try request("GET / HTTP/1.1\r\nHost: a\r\nConnection: close\r\n\r\n").0.keepAlive == false)
        #expect(try request("GET / HTTP/1.1\r\nHost: a\r\nConnection: Keep-Alive, Upgrade\r\n\r\n").0.keepAlive)
        #expect(try request("GET / HTTP/1.0\r\n\r\n").0.keepAlive == false)
        #expect(try request("GET / HTTP/1.0\r\nConnection: keep-alive\r\n\r\n").0.keepAlive)
    }

    @Test func responsesCarrySecurityHeaders() {
        let text = String(decoding: HTTPResponse.error(404, "Not found").serialized(keepAlive: false), as: UTF8.self)
        #expect(text.hasPrefix("HTTP/1.1 404 Not Found\r\n"))
        #expect(text.contains("Content-Security-Policy: default-src 'none'; script-src 'self';"))
        #expect(text.contains("frame-ancestors 'none'"))
        #expect(text.contains("X-Content-Type-Options: nosniff\r\n"))
        #expect(text.contains("Referrer-Policy: no-referrer\r\n"))
        #expect(text.contains("X-Frame-Options: DENY\r\n"))
        #expect(text.contains("Cache-Control: no-store\r\n"))
        #expect(text.contains("Connection: close\r\n"))
        #expect(text.hasSuffix("\r\n\r\n{\"error\":\"Not found\"}"))

        let stream = String(decoding: HTTPResponse.eventStreamHead(), as: UTF8.self)
        #expect(stream.contains("Content-Type: text/event-stream"))
        #expect(stream.contains("Content-Security-Policy:"))
    }

    @Test func headResponsesOmitTheBody() {
        let response = HTTPResponse(status: 200, headers: [("Content-Type", "text/plain")], body: Data("hello".utf8))
        let text = String(decoding: response.serialized(keepAlive: true, includeBody: false), as: UTF8.self)
        #expect(text.contains("Content-Length: 5\r\n"))
        #expect(text.hasSuffix("\r\n\r\n"))
    }
}
