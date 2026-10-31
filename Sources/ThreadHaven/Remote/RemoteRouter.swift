import Foundation

struct RemoteSessionInfo: Equatable, Sendable {
    var id: String
    var title: String
    var project: String
    var status: String
    var agent: String
    var contextPercent: Int
    var lastActivity: Date
    var canSend: Bool

    var json: [String: Any] {
        [
            "id": id,
            "title": title,
            "project": project,
            "status": status,
            "agent": agent,
            "contextPercent": contextPercent,
            "lastActivity": ISO8601DateFormatter().string(from: lastActivity),
            "canSend": canSend,
        ]
    }
}

struct RemoteMessage: Equatable, Sendable {
    var role: String
    var text: String
    var date: Date?

    var json: [String: Any] {
        var object: [String: Any] = ["role": role, "text": text]
        if let date { object["date"] = ISO8601DateFormatter().string(from: date) }
        return object
    }
}

enum PromptOutcome: Equatable {
    case sent
    case notSendable
    case awaitingApproval
    case unknownSession
}

@MainActor
protocol RemoteBackend: AnyObject {
    func remoteSessions() -> [RemoteSessionInfo]
    func remoteMessages(_ id: String) async -> [RemoteMessage]?
    func remotePrompt(_ text: String, to id: String, from device: RemoteDevice) -> PromptOutcome
}

struct StaticFile: Sendable {
    var contentType: String
    var data: Data
}

enum RouteResult {
    case response(HTTPResponse)
    case eventStream(deviceId: String)
}

@MainActor
final class RemoteRouter {
    static let maxPromptCharacters = 4_000

    static let staticRoutes: [String: (file: String, type: String)] = [
        "/": ("index.html", "text/html; charset=utf-8"),
        "/index.html": ("index.html", "text/html; charset=utf-8"),
        "/app.js": ("app.js", "text/javascript; charset=utf-8"),
        "/app.css": ("app.css", "text/css; charset=utf-8"),
        "/sw.js": ("sw.js", "text/javascript; charset=utf-8"),
        "/manifest.webmanifest": ("manifest.webmanifest", "application/manifest+json"),
        "/icon-192.png": ("icon-192.png", "image/png"),
        "/icon-512.png": ("icon-512.png", "image/png"),
    ]

    let auth: RemoteAuthenticator
    weak var backend: RemoteBackend?
    var staticFiles: [String: StaticFile] = [:]
    var allowedHosts: Set<String> = []
    var vapidPublicKey: String?
    var onAuthenticated: ((String) -> Void)?
    var onSubscribe: ((String, PushSubscription) -> Void)?

    init(auth: RemoteAuthenticator) {
        self.auth = auth
    }

    static func loadStaticFiles(from directory: URL) -> [String: StaticFile] {
        var files: [String: StaticFile] = [:]
        for (path, route) in staticRoutes {
            if let data = try? Data(contentsOf: directory.appendingPathComponent(route.file)) {
                files[path] = StaticFile(contentType: route.type, data: data)
            }
        }
        return files
    }

    static func allowedHosts(dnsName: String?, port: UInt16) -> Set<String> {
        var hosts: Set<String> = ["127.0.0.1:\(port)", "localhost:\(port)"]
        if let dnsName {
            hosts.insert(dnsName)
            hosts.insert(dnsName + ":443")
        }
        return hosts
    }

    static func isValidSessionId(_ id: Substring) -> Bool {
        (1...128).contains(id.utf8.count) && id != "." && id != ".."
            && id.utf8.allSatisfy { Data.isBase64URLByte($0) || $0 == UInt8(ascii: ".") }
    }

    static func sanitizePrompt(_ text: String) -> String? {
        let cleaned = String(String.UnicodeScalarView(text.unicodeScalars.filter { scalar in
            scalar == "\n" || scalar == "\t" || !(scalar.properties.generalCategory == .control
                || scalar.properties.generalCategory == .format && scalar.value != 0x200D)
        }))
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxPromptCharacters, !trimmed.hasPrefix("!") else { return nil }
        return trimmed
    }

    func handle(_ request: HTTPRequest, now: Date = .now) async -> RouteResult {
        guard let host = request.header("host")?.lowercased(), allowedHosts.contains(host) else {
            return .response(.error(421, "Unknown host"))
        }
        if request.header("tailscale-funnel-request") != nil {
            return .response(.error(403, "Not available through Funnel"))
        }
        if request.method == "OPTIONS" {
            var response = HTTPResponse(status: 204)
            response.headers.append(("Allow", "GET, HEAD, POST"))
            return .response(response)
        }
        let path = request.path
        if Self.staticRoutes[path] != nil {
            guard request.method == "GET" || request.method == "HEAD" else { return .response(methodNotAllowed("GET, HEAD")) }
            guard let file = staticFiles[path] else { return .response(.error(404, "Not found")) }
            return .response(HTTPResponse(status: 200, headers: [("Content-Type", file.contentType), ("Cache-Control", "no-cache")], body: file.data))
        }
        guard path.hasPrefix("/api/") else { return .response(.error(404, "Not found")) }
        if let site = request.header("sec-fetch-site")?.lowercased(), site != "same-origin", site != "none" {
            return .response(.error(403, "Cross-site requests are not allowed"))
        }

        let deviceId: String
        switch auth.authenticate(request, now: now) {
        case .denied(let status):
            var response = HTTPResponse.error(status, Self.deniedMessage(status))
            if status == 401 { response.headers.append(("WWW-Authenticate", "Bearer")) }
            return .response(response)
        case .allowed(let id):
            deviceId = id
        }
        onAuthenticated?(deviceId)

        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        switch (request.method, parts.count) {
        case (_, 3) where parts[2] == "sessions":
            guard request.method == "GET" else { return .response(methodNotAllowed("GET")) }
            let sessions = backend?.remoteSessions() ?? []
            return .response(.json(["sessions": sessions.map(\.json)]))
        case (_, 5) where parts[2] == "sessions" && parts[4] == "messages":
            guard request.method == "GET" else { return .response(methodNotAllowed("GET")) }
            guard Self.isValidSessionId(parts[3]) else { return .response(.error(404, "Unknown chat")) }
            guard let messages = await backend?.remoteMessages(String(parts[3])) else {
                return .response(.error(404, "Unknown chat"))
            }
            return .response(.json(["messages": messages.map(\.json)]))
        case (_, 5) where parts[2] == "sessions" && parts[4] == "prompt":
            guard request.method == "POST" else { return .response(methodNotAllowed("POST")) }
            guard Self.isValidSessionId(parts[3]) else { return .response(.error(404, "Unknown chat")) }
            return .response(prompt(request, sessionId: String(parts[3]), deviceId: deviceId))
        case (_, 3) where parts[2] == "events":
            guard request.method == "GET" else { return .response(methodNotAllowed("GET")) }
            return .eventStream(deviceId: deviceId)
        case (_, 4) where parts[2] == "push" && parts[3] == "key":
            guard request.method == "GET" else { return .response(methodNotAllowed("GET")) }
            guard let vapidPublicKey else { return .response(.error(503, "Push is not available")) }
            return .response(.json(["key": vapidPublicKey]))
        case (_, 4) where parts[2] == "push" && parts[3] == "subscribe":
            guard request.method == "POST" else { return .response(methodNotAllowed("POST")) }
            return .response(subscribe(request, deviceId: deviceId))
        default:
            return .response(.error(404, "Not found"))
        }
    }

    static func deniedMessage(_ status: Int) -> String {
        switch status {
        case 403: "This Tailscale user is not allowed on this Mac."
        case 429: "Too many failed attempts. Try again later."
        default: "Not authorized"
        }
    }

    private func methodNotAllowed(_ allow: String) -> HTTPResponse {
        var response = HTTPResponse.error(405, "Method not allowed")
        response.headers.append(("Allow", allow))
        return response
    }

    private func jsonBody(_ request: HTTPRequest) -> [String: Any]? {
        guard let type = request.header("content-type")?.lowercased(),
              type == "application/json" || type.hasPrefix("application/json;") else { return nil }
        return (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
    }

    private func prompt(_ request: HTTPRequest, sessionId: String, deviceId: String) -> HTTPResponse {
        guard request.header("content-type")?.lowercased().hasPrefix("application/json") == true else {
            return .error(415, "Expected JSON")
        }
        guard let body = jsonBody(request), let raw = body["text"] as? String else { return .error(400, "Expected a text field") }
        guard let text = Self.sanitizePrompt(raw) else {
            return .error(400, "The prompt is empty, too long or starts with !")
        }
        guard let device = auth.device(deviceId), let backend else { return .error(503, "Unavailable") }
        switch backend.remotePrompt(text, to: sessionId, from: device) {
        case .sent:
            return .json(["sent": true], status: 202)
        case .notSendable:
            return .error(409, "This chat is not running in the foreground of Terminal or iTerm2")
        case .awaitingApproval:
            return .error(409, "This chat is waiting for an approval. Answer it on the Mac.")
        case .unknownSession:
            return .error(404, "Unknown chat")
        }
    }

    private func subscribe(_ request: HTTPRequest, deviceId: String) -> HTTPResponse {
        guard request.header("content-type")?.lowercased().hasPrefix("application/json") == true else {
            return .error(415, "Expected JSON")
        }
        guard let body = jsonBody(request),
              let endpoint = body["endpoint"] as? String,
              let keys = body["keys"] as? [String: Any],
              let p256dh = keys["p256dh"] as? String,
              let authKey = keys["auth"] as? String else { return .error(400, "Expected a push subscription") }
        let subscription = PushSubscription(endpoint: endpoint, p256dh: p256dh, auth: authKey)
        guard WebPush.validate(subscription) else { return .error(400, "Unsupported push subscription") }
        onSubscribe?(deviceId, subscription)
        return .json(["subscribed": true], status: 202)
    }
}
