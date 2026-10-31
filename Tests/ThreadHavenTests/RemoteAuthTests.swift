import Foundation
import Testing
@testable import ThreadHaven

@MainActor
struct RemoteAuthTests {
    private func request(token: String?, login: String? = nil, agent: String? = nil) -> HTTPRequest {
        var headers: [(name: String, value: String)] = [("host", "127.0.0.1:50000")]
        if let token { headers.append(("authorization", "Bearer \(token)")) }
        if let login { headers.append(("tailscale-user-login", login)) }
        if let agent { headers.append(("user-agent", agent)) }
        return HTTPRequest(method: "GET", target: "/api/sessions", version: "HTTP/1.1", headers: headers, body: Data())
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

    @Test func acceptsPairedDevicesAndRejectsOthers() throws {
        let store = MemorySecretStore()
        let auth = RemoteAuthenticator(store: store)
        let device = try auth.pair(name: "Device 1")
        #expect(store.devices[device.id]?.token == device.token)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(auth.authenticate(request(token: device.token, agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0)"), now: now) == .allowed(deviceId: device.id))
        #expect(auth.lastUsed[device.id] == now)
        #expect(auth.device(device.id)?.platform == "iPhone")
        #expect(auth.authenticate(request(token: nil)) == .denied(status: 401))
        #expect(auth.authenticate(request(token: RemoteToken.generate())) == .denied(status: 401))
        #expect(auth.rejected == 2)
    }

    @Test func revokedDevicesAreRejected() throws {
        let store = MemorySecretStore()
        let auth = RemoteAuthenticator(store: store)
        let first = try auth.pair(name: "Device 1")
        let second = try auth.pair(name: "Device 2")
        auth.revoke(first.id)
        #expect(auth.authenticate(request(token: first.token)) == .denied(status: 401))
        #expect(auth.authenticate(request(token: second.token)) == .allowed(deviceId: second.id))
        auth.revokeAll()
        #expect(store.devices.isEmpty)
        #expect(auth.authenticate(request(token: second.token)) == .denied(status: 401))
    }

    @Test func bindsADeviceToTheFirstTailscaleLogin() throws {
        let auth = RemoteAuthenticator(store: MemorySecretStore())
        let device = try auth.pair(name: "Device 1")
        #expect(auth.authenticate(request(token: device.token, login: "Alice@Example.invalid")) == .allowed(deviceId: device.id))
        #expect(auth.device(device.id)?.login == "alice@example.invalid")
        #expect(auth.authenticate(request(token: device.token, login: "alice@example.invalid")) == .allowed(deviceId: device.id))
        #expect(auth.authenticate(request(token: device.token, login: "mallory@example.invalid")) == .denied(status: 403))
        #expect(auth.authenticate(request(token: device.token)) == .denied(status: 403))
    }

    @Test func enforcesTheAllowlist() throws {
        let auth = RemoteAuthenticator(store: MemorySecretStore())
        let device = try auth.pair(name: "Device 1")
        auth.allowlist = RemoteAuthenticator.parseAllowlist("alice@example.invalid, Bob@Example.invalid")
        #expect(auth.allowlist == ["alice@example.invalid", "bob@example.invalid"])
        #expect(auth.authenticate(request(token: device.token)) == .denied(status: 403))
        #expect(auth.authenticate(request(token: device.token, login: "carol@example.invalid")) == .denied(status: 403))
        #expect(auth.authenticate(request(token: device.token, login: "bob@example.invalid")) == .allowed(deviceId: device.id))
    }

    @Test func locksOutAfterRepeatedFailures() throws {
        let auth = RemoteAuthenticator(store: MemorySecretStore())
        let device = try auth.pair(name: "Device 1")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for i in 0..<10 {
            #expect(auth.authenticate(request(token: RemoteToken.generate(), login: "mallory@example.invalid"), now: start.addingTimeInterval(Double(i))) == .denied(status: 401))
        }
        #expect(auth.authenticate(request(token: device.token, login: "mallory@example.invalid"), now: start.addingTimeInterval(11)) == .denied(status: 429))
        #expect(auth.authenticate(request(token: device.token, login: "alice@example.invalid"), now: start.addingTimeInterval(12)) == .allowed(deviceId: device.id))
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
        limiter.recordSuccess("a")
    }

    @Test func detectsPlatforms() {
        #expect(RemoteAuthenticator.platform(from: "Mozilla/5.0 (Linux; Android 15)") == "Android")
        #expect(RemoteAuthenticator.platform(from: "Mozilla/5.0 (iPad; CPU OS 18_0)") == "iPad")
        #expect(RemoteAuthenticator.platform(from: nil) == "Browser")
    }
}
