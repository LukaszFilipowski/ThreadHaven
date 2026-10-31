import Foundation
import Testing
@testable import ThreadHaven

@MainActor
final class FakeBackend: RemoteBackend {
    var sessions = [
        RemoteSessionInfo(id: "11111111-aaaa-bbbb-cccc-000000000001", title: "Refactor the parser", project: "sample-app", status: "finished", agent: "claude", contextPercent: 42, lastActivity: Date(timeIntervalSince1970: 1_800_000_000), canSend: true),
        RemoteSessionInfo(id: "11111111-aaaa-bbbb-cccc-000000000002", title: "Old chat", project: "sample-app", status: "closed", agent: "claude", contextPercent: 3, lastActivity: Date(timeIntervalSince1970: 1_700_000_000), canSend: false),
    ]
    var prompts: [(text: String, id: String, device: String)] = []

    func remoteSessions() -> [RemoteSessionInfo] { sessions }

    func remoteMessages(_ id: String) async -> [RemoteMessage]? {
        guard sessions.contains(where: { $0.id == id }) else { return nil }
        return [RemoteMessage(role: "user", text: "<b>hello</b>", date: nil), RemoteMessage(role: "assistant", text: "Hi", date: nil)]
    }

    func remotePrompt(_ text: String, to id: String, from device: RemoteDevice) -> PromptOutcome {
        guard let session = sessions.first(where: { $0.id == id }) else { return .unknownSession }
        if session.status == "needsInput" { return .awaitingApproval }
        guard session.canSend else { return .notSendable }
        prompts.append((text, id, device.id))
        return .sent
    }
}

@MainActor
struct RemoteRouterTests {
    let backend = FakeBackend()
    let auth = RemoteAuthenticator(store: MemorySecretStore())
    let router: RemoteRouter
    let device: RemoteDevice
    let token: String

    init() throws {
        router = RemoteRouter(auth: auth)
        router.backend = backend
        router.allowedHosts = RemoteRouter.allowedHosts(dnsName: "example-mac.example.ts.net", port: 50_000)
        router.staticFiles = ["/": StaticFile(contentType: "text/html; charset=utf-8", data: Data("<!doctype html>".utf8))]
        router.vapidPublicKey = "BPUBLICKEY"
        auth.ownLogin = "alice@example.invalid"
        let paired = try auth.pair(name: "Device 1")
        device = paired.device
        token = paired.token
    }

    private func send(
        _ method: String,
        _ target: String,
        token: String? = nil,
        host: String = "example-mac.example.ts.net",
        contentType: String? = nil,
        body: String = "",
        extra: [(name: String, value: String)] = [("tailscale-user-login", "alice@example.invalid")]
    ) async -> RouteResult {
        var headers: [(name: String, value: String)] = [("host", host)] + extra
        if let token { headers.append(("authorization", "Bearer \(token)")) }
        if let contentType { headers.append(("content-type", contentType)) }
        let request = HTTPRequest(method: method, target: target, version: "HTTP/1.1", headers: headers, body: Data(body.utf8))
        return await router.handle(request)
    }

    private func response(_ result: RouteResult) -> HTTPResponse? {
        if case .response(let response) = result { return response }
        return nil
    }

    private func json(_ result: RouteResult) -> [String: Any]? {
        response(result).flatMap { try? JSONSerialization.jsonObject(with: $0.body) as? [String: Any] }
    }

    @Test func servesTheAppShellWithoutAToken() async {
        let result = response(await send("GET", "/"))
        #expect(result?.status == 200)
        #expect(result?.body == Data("<!doctype html>".utf8))
        #expect(response(await send("GET", "/app.js"))?.status == 404)
        #expect(response(await send("POST", "/"))?.status == 405)
        #expect(response(await send("GET", "/../etc/passwd"))?.status == 404)
        #expect(response(await send("GET", "/Web/index.html"))?.status == 404)
    }

    @Test func rejectsUnknownHosts() async {
        #expect(response(await send("GET", "/", host: "evil.example.invalid"))?.status == 421)
        #expect(response(await send("GET", "/api/sessions", token: token, host: "evil.example.invalid"))?.status == 421)
        #expect(response(await send("GET", "/", host: "127.0.0.1:50000"))?.status == 200)
        #expect(response(await send("GET", "/", host: "localhost:50001"))?.status == 421)
    }

    @Test func apiRequiresAToken() async {
        let result = response(await send("GET", "/api/sessions"))
        #expect(result?.status == 401)
        #expect(result?.headers.contains { $0.name == "WWW-Authenticate" } == true)
        #expect(response(await send("GET", "/api/sessions", token: RemoteToken.generate()))?.status == 401)
        #expect(response(await send("GET", "/api/events"))?.status == 401)
        #expect(response(await send("POST", "/api/push/subscribe"))?.status == 401)
    }

    @Test func listsSessions() async throws {
        let body = try #require(json(await send("GET", "/api/sessions", token: token)))
        let sessions = try #require(body["sessions"] as? [[String: Any]])
        #expect(sessions.count == 2)
        #expect(sessions[0]["title"] as? String == "Refactor the parser")
        #expect(sessions[0]["canSend"] as? Bool == true)
        #expect(sessions[0]["contextPercent"] as? Int == 42)
        #expect(sessions[0]["lastActivity"] as? String == "2027-01-15T08:00:00Z")
        #expect(response(await send("POST", "/api/sessions", token: token))?.status == 405)
    }

    @Test func returnsMessagesAsPlainJSONText() async throws {
        let id = backend.sessions[0].id
        let body = try #require(json(await send("GET", "/api/sessions/\(id)/messages", token: token)))
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.first?["text"] as? String == "<b>hello</b>")
        #expect(response(await send("GET", "/api/sessions/unknown/messages", token: token))?.status == 404)
        #expect(response(await send("GET", "/api/sessions/..%2F..%2Fsecret/messages", token: token))?.status == 404)
        #expect(response(await send("GET", "/api/sessions/../messages", token: token))?.status == 404)
    }

    @Test func sendsPromptsToSendableChats() async {
        let id = backend.sessions[0].id
        let result = response(await send("POST", "/api/sessions/\(id)/prompt", token: token, contentType: "application/json", body: #"{"text":"  Run the tests \u001b[31m please  "}"#))
        #expect(result?.status == 202)
        #expect(backend.prompts.first?.text == "Run the tests [31m please")
        #expect(backend.prompts.first?.device == device.id)
    }

    @Test func refusesUnsafeOrInvalidPrompts() async {
        let id = backend.sessions[0].id
        let path = "/api/sessions/\(id)/prompt"
        #expect(response(await send("POST", path, token: token, contentType: "text/plain", body: #"{"text":"hi"}"#))?.status == 415)
        #expect(response(await send("POST", path, token: token, contentType: "application/json", body: "not json"))?.status == 400)
        #expect(response(await send("POST", path, token: token, contentType: "application/json", body: #"{"text":"   "}"#))?.status == 400)
        #expect(response(await send("POST", path, token: token, contentType: "application/json", body: #"{"text":"! rm -rf ~"}"#))?.status == 400)
        let long = String(repeating: "a", count: RemoteRouter.maxPromptCharacters + 1)
        #expect(response(await send("POST", path, token: token, contentType: "application/json", body: #"{"text":"\#(long)"}"#))?.status == 400)
        #expect(response(await send("POST", "/api/sessions/\(backend.sessions[1].id)/prompt", token: token, contentType: "application/json", body: #"{"text":"hi"}"#))?.status == 409)
        #expect(response(await send("POST", "/api/sessions/missing/prompt", token: token, contentType: "application/json", body: #"{"text":"hi"}"#))?.status == 404)
        #expect(response(await send("GET", path, token: token))?.status == 405)
        #expect(backend.prompts.isEmpty)
    }

    @Test func sanitizesPrompts() {
        #expect(RemoteRouter.sanitizePrompt("line one\nline two") == "line one\nline two")
        #expect(RemoteRouter.sanitizePrompt("a\u{202E}b\u{0007}c") == "abc")
        #expect(RemoteRouter.sanitizePrompt("👩‍💻 ok") == "👩‍💻 ok")
        #expect(RemoteRouter.sanitizePrompt("\u{0}!x") == nil)
    }

    @Test func opensEventStreams() async {
        guard case .eventStream(let id) = await send("GET", "/api/events", token: token) else {
            Issue.record("Expected an event stream")
            return
        }
        #expect(id == device.id)
    }

    @Test func registersValidPushSubscriptions() async {
        var received: [(String, PushSubscription)] = []
        router.onSubscribe = { received.append(($0, $1)) }
        let key = "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4"
        let good = #"{"endpoint":"https://web.push.apple.com/abc","keys":{"p256dh":"\#(key)","auth":"BTBZMqHH6r4Tts7J_aSIgg"}}"#
        let loopback = #"{"endpoint":"https://127.0.0.1/abc","keys":{"p256dh":"\#(key)","auth":"BTBZMqHH6r4Tts7J_aSIgg"}}"#
        #expect(response(await send("POST", "/api/push/subscribe", token: token, contentType: "application/json", body: loopback))?.status == 400)
        #expect(response(await send("POST", "/api/push/subscribe", token: token, contentType: "application/json", body: good))?.status == 202)
        #expect(received.count == 1)
        #expect(received.first?.0 == device.id)
        #expect(json(await send("GET", "/api/push/key", token: token))?["key"] as? String == "BPUBLICKEY")
    }

    @Test func refusesFunnelRequestsBeforeAnythingElse() async {
        let funnel = [(name: "tailscale-funnel-request", value: "?1"), (name: "tailscale-user-login", value: "alice@example.invalid")]
        #expect(response(await send("GET", "/", extra: funnel))?.status == 403)
        #expect(response(await send("GET", "/api/sessions", token: token, extra: funnel))?.status == 403)
        #expect(auth.rejected == 0)
    }

    @Test func answersPreflightAndCrossSiteRequestsWithoutCounting() async {
        let options = response(await send("OPTIONS", "/api/sessions"))
        #expect(options?.status == 204)
        #expect(options?.headers.contains { $0.name.hasPrefix("Access-Control") } == false)
        for site in ["cross-site", "same-site"] {
            let extra = [(name: "sec-fetch-site", value: site), (name: "tailscale-user-login", value: "alice@example.invalid")]
            for _ in 0..<20 {
                #expect(response(await send("GET", "/api/sessions", token: RemoteToken.generate(), extra: extra))?.status == 403)
            }
        }
        #expect(auth.rejected == 0)
        let sameOrigin = [(name: "sec-fetch-site", value: "same-origin"), (name: "tailscale-user-login", value: "alice@example.invalid")]
        #expect(response(await send("GET", "/api/sessions", token: token, extra: sameOrigin))?.status == 200)
        let navigation = [(name: "sec-fetch-site", value: "cross-site")]
        #expect(response(await send("GET", "/", extra: navigation))?.status == 200)
    }

    @Test func refusesPromptsWhileAChatWaitsForApproval() async {
        backend.sessions[0].status = "needsInput"
        let result = response(await send("POST", "/api/sessions/\(backend.sessions[0].id)/prompt", token: token, contentType: "application/json", body: #"{"text":"1"}"#))
        #expect(result?.status == 409)
        #expect(backend.prompts.isEmpty)
    }

    @Test func unknownApiPathsAreNotFound() async {
        #expect(response(await send("GET", "/api/files", token: token))?.status == 404)
        #expect(response(await send("GET", "/api/sessions/x/y/z", token: token))?.status == 404)
        #expect(response(await send("GET", "/other"))?.status == 404)
    }
}
