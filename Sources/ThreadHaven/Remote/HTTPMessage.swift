import Foundation

struct HTTPRequest: Sendable, Equatable {
    var method: String
    var target: String
    var version: String
    var headers: [(name: String, value: String)]
    var body: Data

    var path: String {
        target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? target
    }

    func header(_ name: String) -> String? {
        let lowered = name.lowercased()
        return headers.first { $0.name == lowered }?.value
    }

    func headerCount(_ name: String) -> Int {
        let lowered = name.lowercased()
        return headers.filter { $0.name == lowered }.count
    }

    var keepAlive: Bool {
        let tokens = (header("connection") ?? "").lowercased()
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if version == "HTTP/1.0" { return tokens.contains("keep-alive") }
        return !tokens.contains("close")
    }

    static func == (lhs: HTTPRequest, rhs: HTTPRequest) -> Bool {
        lhs.method == rhs.method && lhs.target == rhs.target && lhs.version == rhs.version
            && lhs.body == rhs.body
            && lhs.headers.map(\.name) == rhs.headers.map(\.name)
            && lhs.headers.map(\.value) == rhs.headers.map(\.value)
    }
}

enum HTTPParseResult: Equatable {
    case incomplete
    case complete(HTTPRequest, consumed: Int)
    case failure(Int)
}

enum HTTPParser {
    static let maxHeaderBytes = 16_384
    static let maxHeaderCount = 64
    static let maxTargetLength = 2_048
    static let maxBodyBytes = 65_536

    private static let crlfcrlf: [UInt8] = [13, 10, 13, 10]

    static func parse(_ buffer: Data) -> HTTPParseResult {
        let bytes = [UInt8](buffer)
        guard let headerEnd = find(crlfcrlf, in: bytes, limit: maxHeaderBytes + 4) else {
            return bytes.count > maxHeaderBytes ? .failure(431) : .incomplete
        }
        guard headerEnd <= maxHeaderBytes else { return .failure(431) }

        let lines = split(Array(bytes[0..<headerEnd]))
        guard let requestLine = lines.first, let (method, target, version) = parseRequestLine(requestLine) else {
            return .failure(400)
        }
        guard version == "HTTP/1.1" || version == "HTTP/1.0" else { return .failure(505) }
        guard target.utf8.count <= maxTargetLength else { return .failure(414) }

        var headers: [(name: String, value: String)] = []
        for line in lines.dropFirst() {
            guard headers.count < maxHeaderCount else { return .failure(431) }
            guard let header = parseHeader(line) else { return .failure(400) }
            headers.append(header)
        }

        var request = HTTPRequest(method: method, target: target, version: version, headers: headers, body: Data())
        if request.header("transfer-encoding") != nil { return .failure(501) }
        if version == "HTTP/1.1" && request.headerCount("host") != 1 { return .failure(400) }
        if request.headerCount("host") > 1 { return .failure(400) }

        var length = 0
        switch request.headerCount("content-length") {
        case 0:
            length = 0
        case 1:
            let raw = request.header("content-length") ?? ""
            guard !raw.isEmpty, raw.utf8.count <= 10, raw.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }), let value = Int(raw) else {
                return .failure(400)
            }
            guard value <= maxBodyBytes else { return .failure(413) }
            length = value
        default:
            return .failure(400)
        }

        let bodyStart = headerEnd + 4
        guard bytes.count >= bodyStart + length else { return .incomplete }
        request.body = Data(bytes[bodyStart..<(bodyStart + length)])
        return .complete(request, consumed: bodyStart + length)
    }

    private static func find(_ needle: [UInt8], in bytes: [UInt8], limit: Int) -> Int? {
        let end = min(bytes.count, limit) - needle.count
        guard end >= 0 else { return nil }
        var i = 0
        while i <= end {
            if bytes[i] == needle[0] && bytes[i + 1] == needle[1] && bytes[i + 2] == needle[2] && bytes[i + 3] == needle[3] {
                return i
            }
            i += 1
        }
        return nil
    }

    private static func split(_ bytes: [UInt8]) -> [[UInt8]] {
        var lines: [[UInt8]] = []
        var current: [UInt8] = []
        var i = 0
        while i < bytes.count {
            if bytes[i] == 13 && i + 1 < bytes.count && bytes[i + 1] == 10 {
                lines.append(current)
                current = []
                i += 2
            } else {
                current.append(bytes[i])
                i += 1
            }
        }
        lines.append(current)
        return lines
    }

    private static func isTokenByte(_ b: UInt8) -> Bool {
        switch b {
        case 48...57, 65...90, 97...122: true
        case UInt8(ascii: "!"), UInt8(ascii: "#"), UInt8(ascii: "$"), UInt8(ascii: "%"), UInt8(ascii: "&"),
             UInt8(ascii: "'"), UInt8(ascii: "*"), UInt8(ascii: "+"), UInt8(ascii: "-"), UInt8(ascii: "."),
             UInt8(ascii: "^"), UInt8(ascii: "_"), UInt8(ascii: "`"), UInt8(ascii: "|"), UInt8(ascii: "~"): true
        default: false
        }
    }

    private static func parseRequestLine(_ line: [UInt8]) -> (String, String, String)? {
        let parts = line.split(separator: 32, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let method = parts[0], target = parts[1], version = parts[2]
        guard !method.isEmpty, method.count <= 16, method.allSatisfy({ $0 >= 65 && $0 <= 90 }) else { return nil }
        guard target.first == UInt8(ascii: "/"), target.allSatisfy({ $0 > 32 && $0 < 127 }) else { return nil }
        guard version.count == 8, version.allSatisfy({ $0 > 32 && $0 < 127 }) else { return nil }
        return (String(decoding: method, as: UTF8.self), String(decoding: target, as: UTF8.self), String(decoding: version, as: UTF8.self))
    }

    private static func parseHeader(_ line: [UInt8]) -> (name: String, value: String)? {
        guard let colon = line.firstIndex(of: UInt8(ascii: ":")), colon > 0 else { return nil }
        let name = line[..<colon]
        guard name.allSatisfy(isTokenByte) else { return nil }
        var value = line[(colon + 1)...]
        guard value.allSatisfy({ $0 == 9 || ($0 >= 32 && $0 != 127) }) else { return nil }
        while let first = value.first, first == 32 || first == 9 { value = value.dropFirst() }
        while let last = value.last, last == 32 || last == 9 { value = value.dropLast() }
        return (String(decoding: name, as: UTF8.self).lowercased(), String(decoding: value, as: UTF8.self))
    }
}

struct HTTPResponse: Sendable {
    var status: Int
    var headers: [(name: String, value: String)] = []
    var body = Data()

    static let securityHeaders: [(name: String, value: String)] = [
        ("Content-Security-Policy", "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; manifest-src 'self'; worker-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"),
        ("X-Content-Type-Options", "nosniff"),
        ("X-Frame-Options", "DENY"),
        ("Referrer-Policy", "no-referrer"),
        ("Cross-Origin-Opener-Policy", "same-origin"),
        ("Cross-Origin-Resource-Policy", "same-origin"),
        ("Permissions-Policy", "camera=(), microphone=(), geolocation=(), payment=(), usb=()"),
        ("Strict-Transport-Security", "max-age=31536000"),
    ]

    static func json(_ object: Any, status: Int = 200) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        return HTTPResponse(status: status, headers: [("Content-Type", "application/json; charset=utf-8"), ("Cache-Control", "no-store")], body: data)
    }

    static func error(_ status: Int, _ message: String) -> HTTPResponse {
        json(["error": message], status: status)
    }

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 202: "Accepted"
        case 204: "No Content"
        case 304: "Not Modified"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 408: "Request Timeout"
        case 409: "Conflict"
        case 413: "Content Too Large"
        case 414: "URI Too Long"
        case 415: "Unsupported Media Type"
        case 421: "Misdirected Request"
        case 429: "Too Many Requests"
        case 431: "Request Header Fields Too Large"
        case 500: "Internal Server Error"
        case 501: "Not Implemented"
        case 503: "Service Unavailable"
        case 505: "HTTP Version Not Supported"
        default: "Status"
        }
    }

    func serialized(keepAlive: Bool, includeBody: Bool = true) -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        for (name, value) in Self.securityHeaders + headers {
            head += "\(name): \(value)\r\n"
        }
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: \(keepAlive ? "keep-alive" : "close")\r\n\r\n"
        var data = Data(head.utf8)
        if includeBody { data.append(body) }
        return data
    }

    static func eventStreamHead() -> Data {
        var head = "HTTP/1.1 200 OK\r\n"
        for (name, value) in securityHeaders {
            head += "\(name): \(value)\r\n"
        }
        head += "Content-Type: text/event-stream; charset=utf-8\r\nCache-Control: no-store\r\nX-Accel-Buffering: no\r\nConnection: close\r\n\r\n"
        return Data(head.utf8)
    }
}
