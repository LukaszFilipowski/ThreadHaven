import Foundation
import Testing
@testable import ThreadHaven

@MainActor
struct RemoteAuthTests {
    private let owner = "alice@example.invalid"

    private func request(token: String?, login: String? = "alice@example.invalid", agent: String? = nil, raw: String? = nil) -> HTTPRequest {
        var headers: [(name: String, value: String)] = [("host", "127.0.0.1:50000")]
        if let token { headers.append(("authorization", "Bearer \(token)")) }
        if let raw { headers.append(("authorization", raw)) }
        if let login { headers.append(("tailscale-user-login", login)) }
        if let agent { headers.append(("user-agent", agent)) }
        return HTTPRequest(method: "GET", target: "/api/sessions", version: "HTTP/1.1", headers: headers, body: Data())
    }

    private func authenticator(_ store: MemorySecretStore = MemorySecretStore()) -> RemoteAuthenticator {
        let auth = RemoteAuthenticator(store: store)
        auth.ownLogin = owner
        return auth
    }

    @Test func tokensAreRandom256BitBase64URL() {
        let a = RemoteToken.generate()
        let b = RemoteToken.generate()
        #expect(a != b)
        #expect(a.utf8.count == 43)
        #expect(Data(base64URL: a)?.count == 32)
    }

    @Test func parsesBearerHeaders() {
        let token = RemoteToken.generate()
        #expect(RemoteToken.bearer(from: "Bearer \(token)") == token)
        #expect(RemoteToken.bearer(from: "bearer \(token)") == token)
        #expect(RemoteToken.bearer(from: "Basic \(token)") == nil)
        #expect(RemoteToken.bearer(from: "Bearer") == nil)
        #expect(RemoteToken.bearer(from: "Bearer short") == nil)
        #expect(RemoteToken.bearer(from: "Bearer \(token) extra") == nil)
        #expect(RemoteToken.bearer(from: "Bearer abc$defghijklmnopqrstu") == nil)
        #expect(RemoteToken.bearer(from: nil) == nil)
    }

    @Test func comparesTokensByValue() {
        #expect(RemoteToken.constantTimeEquals("abcdefghijklmnop", "abcdefghijklmnop"))
        #expect(!RemoteToken.constantTimeEquals("abcdefghijklmnop", "abcdefghijklmnoq"))
        #expect(!RemoteToken.constantTimeEquals("abcdefghijklmnop", "abcdefghijklmnopq"))
        #expect(!RemoteToken.constantTimeEquals("", "a"))
    }

    @Test func storesOnlyTokenHashes() throws {
        let store = MemorySecretStore()
        let auth = authenticator(store)
        let paired = try auth.pair(name: "Device 1")
        let saved = try #require(store.devices[paired.device.id])
        #expect(saved.tokenHash == RemoteToken.hash(paired.token))
        #expect(saved.tokenHash != paired.token)
        let encoded = String(decoding: try JSONEncoder().encode(saved), as: UTF8.self)
        #expect(!encoded.contains(paired.token))
    }

    @Test func legacyItemsWithPlainTokensAreNotLoaded() throws {
        let legacy = #"{"id":"A","name":"Device 1","token":"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ","created":0}"#
        #expect(RemoteDevice.decode(Data(legacy.utf8)) == nil)
        let badHash = #"{"id":"A","name":"Device 1","tokenHash":"short","created":0}"#
        #expect(RemoteDevice.decode(Data(badHash.utf8)) == nil)
        let current = RemoteDevice(id: "B", name: "Device 2", tokenHash: RemoteToken.hash(RemoteToken.generate()), created: Date(timeIntervalSince1970: 0))
        #expect(RemoteDevice.decode(try JSONEncoder().encode(current)) == current)
    }

    @Test func revokeAllClearsDevicesTheAuthenticatorDoesNotKnow() throws {
        let store = MemorySecretStore()
        let auth = authenticator(store)
        _ = try auth.pair(name: "Device 1")
        try store.save(RemoteDevice(id: "stray", name: "Stray", tokenHash: RemoteToken.hash(RemoteToken.generate()), created: Date()))
        auth.revokeAll()
        #expect(store.devices.isEmpty)
        #expect(auth.devices.isEmpty)
    }

    @Test func acceptsPairedDevicesAndRejectsOthers() throws {
        let auth = authenticator()
        let paired = try auth.pair(name: "Device 1")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(auth.authenticate(request(token: paired.token, agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0)"), now: now) == .allowed(deviceId: paired.device.id))
        #expect(auth.lastUsed[paired.device.id] == now)
        #expect(auth.device(paired.device.id)?.platform == "iPhone")
        #expect(auth.device(paired.device.id)?.login == owner)
        #expect(auth.authenticate(request(token: nil)) == .denied(status: 401))
        #expect(auth.authenticate(request(token: RemoteToken.generate())) == .denied(status: 401))
        #expect(auth.authenticate(request(token: paired.device.tokenHash)) == .denied(status: 401))
        #expect(auth.rejected == 3)
    }

    @Test func revokedDevicesAreRejected() throws {
        let store = MemorySecretStore()
        let auth = authenticator(store)
        let first = try auth.pair(name: "Device 1")
        let second = try auth.pair(name: "Device 2")
        auth.revoke(first.device.id)
        #expect(auth.authenticate(request(token: first.token)) == .denied(status: 401))
        #expect(auth.authenticate(request(token: second.token)) == .allowed(deviceId: second.device.id))
        auth.revokeAll()
        #expect(store.devices.isEmpty)
        #expect(auth.authenticate(request(token: second.token)) == .denied(status: 401))
    }

    @Test func defaultsToTheMacOwnersLogin() throws {
        let auth = authenticator()
        let paired = try auth.pair(name: "Device 1")
        #expect(auth.effectiveAllowlist == [owner])
        #expect(auth.authenticate(request(token: paired.token, login: "Alice@Example.invalid")) == .allowed(deviceId: paired.device.id))
        #expect(auth.authenticate(request(token: paired.token, login: "mallory@example.invalid")) == .denied(status: 403))
        #expect(auth.authenticate(request(token: paired.token, login: nil)) == .denied(status: 403))
    }

    @Test func refusesEverythingWithoutAKnownLogin() throws {
        let auth = RemoteAuthenticator(store: MemorySecretStore())
        let paired = try auth.pair(name: "Device 1")
        #expect(auth.effectiveAllowlist.isEmpty)
        #expect(auth.authenticate(request(token: paired.token)) == .denied(status: 403))
    }

    @Test func explicitAllowlistReplacesTheDefault() throws {
        let auth = authenticator()
        let paired = try auth.pair(name: "Device 1")
        auth.allowlist = RemoteAuthenticator.parseAllowlist("carol@example.invalid, Bob@Example.invalid")
        #expect(auth.allowlist == ["carol@example.invalid", "bob@example.invalid"])
        #expect(auth.authenticate(request(token: paired.token)) == .denied(status: 403))
        #expect(auth.authenticate(request(token: paired.token, login: "bob@example.invalid")) == .allowed(deviceId: paired.device.id))
    }

    @Test func wrongTokensLockOutOnlyWrongTokens() throws {
        let auth = authenticator()
        let paired = try auth.pair(name: "Device 1")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for i in 0..<10 {
            #expect(auth.authenticate(request(token: RemoteToken.generate()), now: start.addingTimeInterval(Double(i))) == .denied(status: 401))
        }
        #expect(auth.authenticate(request(token: RemoteToken.generate()), now: start.addingTimeInterval(11)) == .denied(status: 429))
        #expect(auth.authenticate(request(token: paired.token), now: start.addingTimeInterval(12)) == .allowed(deviceId: paired.device.id))
    }

    @Test func requestsWithoutABearerTokenAreNotCounted() throws {
        let auth = authenticator()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for i in 0..<50 {
            #expect(auth.authenticate(request(token: nil, raw: i % 2 == 0 ? nil : "Bearer x"), now: start.addingTimeInterval(Double(i))) == .denied(status: 401))
        }
        #expect(auth.authenticate(request(token: RemoteToken.generate()), now: start.addingTimeInterval(60)) == .denied(status: 401))
    }

    @Test func limiterWindowAndLockoutExpire() {
        var limiter = FailureLimiter(maxFailures: 3, window: 60, lockout: 120)
        let start = Date(timeIntervalSince1970: 0)
        limiter.recordFailure("a", now: start)
        limiter.recordFailure("a", now: start.addingTimeInterval(1))
        limiter.recordFailure("a", now: start.addingTimeInterval(100))
        #expect(!limiter.isLocked("a", now: start.addingTimeInterval(100)))
        limiter.recordFailure("a", now: start.addingTimeInterval(101))
        limiter.recordFailure("a", now: start.addingTimeInterval(102))
        #expect(limiter.isLocked("a", now: start.addingTimeInterval(103)))
        #expect(!limiter.isLocked("b", now: start.addingTimeInterval(103)))
        #expect(!limiter.isLocked("a", now: start.addingTimeInterval(223)))
    }

    @Test func limiterStateStaysBounded() {
        var limiter = FailureLimiter(maxFailures: 1, window: 60, lockout: 600)
        limiter.maxKeys = 8
        let now = Date(timeIntervalSince1970: 0)
        for i in 0..<100 { limiter.recordFailure("key-\(i)", now: now) }
        #expect(limiter.lockedKeyCount <= 8)
        #expect(limiter.isLocked("key-99", now: now))
    }

    @Test func detectsPlatforms() {
        #expect(RemoteAuthenticator.platform(from: "Mozilla/5.0 (Linux; Android 15)") == "Android")
        #expect(RemoteAuthenticator.platform(from: "Mozilla/5.0 (iPad; CPU OS 18_0)") == "iPad")
        #expect(RemoteAuthenticator.platform(from: nil) == "Browser")
    }
}
