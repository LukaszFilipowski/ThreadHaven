import CryptoKit
import Foundation
import os
import Security

enum RemoteLog {
    static let logger = Logger(subsystem: "app.threadhaven", category: "remote-access")
}

extension Data {
    init?(base64URL string: String) {
        guard string.utf8.allSatisfy({ Self.isBase64URLByte($0) || $0 == UInt8(ascii: "=") }) else { return nil }
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 = base64.replacingOccurrences(of: "=", with: "")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }

    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func isBase64URLByte(_ b: UInt8) -> Bool {
        (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b == UInt8(ascii: "-") || b == UInt8(ascii: "_")
    }

    static func random(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        if SecRandomCopyBytes(kSecRandomDefault, count, &bytes) != errSecSuccess {
            var generator = SystemRandomNumberGenerator()
            for i in bytes.indices { bytes[i] = UInt8.random(in: .min ... .max, using: &generator) }
        }
        return Data(bytes)
    }
}

struct PushSubscription: Codable, Sendable, Equatable {
    var endpoint: String
    var p256dh: String
    var auth: String
}

struct RemoteDevice: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var name: String
    var token: String
    var created: Date
    var login: String?
    var platform: String?
    var push: PushSubscription?
}

protocol RemoteSecretStore: AnyObject {
    func loadDevices() -> [RemoteDevice]
    func save(_ device: RemoteDevice) throws
    func delete(id: String)
    func loadVAPIDKey() -> Data?
    func saveVAPIDKey(_ key: Data) throws
}

final class MemorySecretStore: RemoteSecretStore {
    var devices: [String: RemoteDevice] = [:]
    var vapid: Data?

    func loadDevices() -> [RemoteDevice] { devices.values.sorted { $0.created < $1.created } }
    func save(_ device: RemoteDevice) throws { devices[device.id] = device }
    func delete(id: String) { devices[id] = nil }
    func loadVAPIDKey() -> Data? { vapid }
    func saveVAPIDKey(_ key: Data) throws { vapid = key }
}

final class KeychainSecretStore: RemoteSecretStore {
    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
        }
    }

    private let deviceService = "app.threadhaven.remote-access.device"
    private let vapidService = "app.threadhaven.remote-access.vapid"

    func loadDevices() -> [RemoteDevice] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: deviceService,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        let decoder = JSONDecoder()
        return items
            .compactMap { $0[kSecAttrAccount as String] as? String }
            .compactMap { read(service: deviceService, account: $0).flatMap { try? decoder.decode(RemoteDevice.self, from: $0) } }
            .sorted { $0.created < $1.created }
    }

    func save(_ device: RemoteDevice) throws {
        try store(service: deviceService, account: device.id, data: JSONEncoder().encode(device))
    }

    func delete(id: String) {
        remove(service: deviceService, account: id)
    }

    func loadVAPIDKey() -> Data? {
        read(service: vapidService, account: "vapid")
    }

    private func read(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    func saveVAPIDKey(_ key: Data) throws {
        try store(service: vapidService, account: "vapid", data: key)
    }

    private func store(service: String, account: String, data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "ThreadHaven remote access"
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    private func remove(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct FailureLimiter {
    var maxFailures = 10
    var window: TimeInterval = 300
    var lockout: TimeInterval = 900
    var maxKeys = 512
    private var failures: [String: [Date]] = [:]
    private var lockedUntil: [String: Date] = [:]

    init(maxFailures: Int = 10, window: TimeInterval = 300, lockout: TimeInterval = 900) {
        self.maxFailures = maxFailures
        self.window = window
        self.lockout = lockout
    }

    func isLocked(_ key: String, now: Date) -> Bool {
        (lockedUntil[key] ?? .distantPast) > now
    }

    mutating func recordFailure(_ key: String, now: Date) {
        if failures[key] == nil && failures.count >= maxKeys { prune(now: now) }
        if failures[key] == nil && failures.count >= maxKeys { failures.removeAll() }
        var recent = (failures[key] ?? []).filter { now.timeIntervalSince($0) < window }
        recent.append(now)
        if recent.count >= maxFailures {
            lockedUntil[key] = now.addingTimeInterval(lockout)
            recent.removeAll()
        }
        failures[key] = recent
    }

    mutating func recordSuccess(_ key: String) {
        failures[key] = nil
    }

    private mutating func prune(now: Date) {
        failures = failures.filter { $0.value.contains { now.timeIntervalSince($0) < window } }
        lockedUntil = lockedUntil.filter { $0.value > now }
    }
}

enum RemoteToken {
    static func generate() -> String {
        Data.random(count: 32).base64URLEncoded
    }

    static func bearer(from header: String?) -> String? {
        guard let header else { return nil }
        let parts = header.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 2, parts[0].lowercased() == "bearer" else { return nil }
        let token = String(parts[1])
        guard (16...128).contains(token.utf8.count), token.utf8.allSatisfy(Data.isBase64URLByte) else { return nil }
        return token
    }

    static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let x = Array(SHA256.hash(data: Data(a.utf8)))
        let y = Array(SHA256.hash(data: Data(b.utf8)))
        var difference: UInt8 = 0
        for i in 0..<x.count { difference |= x[i] ^ y[i] }
        return difference == 0
    }
}

enum AuthResult: Equatable {
    case allowed(deviceId: String)
    case denied(status: Int)
}

@MainActor
final class RemoteAuthenticator {
    private let store: RemoteSecretStore
    private(set) var devices: [RemoteDevice]
    private(set) var lastUsed: [String: Date] = [:]
    private(set) var rejected = 0
    private(set) var lastRejectedAt: Date?
    var allowlist: [String] = []
    private var limiter = FailureLimiter()

    init(store: RemoteSecretStore) {
        self.store = store
        self.devices = store.loadDevices()
    }

    func reload() {
        devices = store.loadDevices()
    }

    func pair(name: String, now: Date = .now) throws -> RemoteDevice {
        let device = RemoteDevice(id: UUID().uuidString, name: name, token: RemoteToken.generate(), created: now)
        try store.save(device)
        devices.append(device)
        return device
    }

    func revoke(_ id: String) {
        store.delete(id: id)
        devices.removeAll { $0.id == id }
        lastUsed[id] = nil
    }

    func revokeAll() {
        for device in store.loadDevices() { store.delete(id: device.id) }
        for device in devices { store.delete(id: device.id) }
        devices.removeAll()
        lastUsed.removeAll()
    }

    func device(_ id: String) -> RemoteDevice? {
        devices.first { $0.id == id }
    }

    func update(_ device: RemoteDevice) {
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        devices[index] = device
        try? store.save(device)
    }

    static func normalizedLogin(_ login: String?) -> String? {
        guard let login = login?.trimmingCharacters(in: .whitespaces).lowercased(), !login.isEmpty else { return nil }
        return login
    }

    static func parseAllowlist(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == " " })
            .compactMap { normalizedLogin(String($0)) }
    }

    func authenticate(_ request: HTTPRequest, now: Date = .now) -> AuthResult {
        let login = Self.normalizedLogin(request.header("tailscale-user-login"))
        let key = login ?? "local"
        if limiter.isLocked(key, now: now) {
            reject(now: now)
            return .denied(status: 429)
        }
        guard let token = RemoteToken.bearer(from: request.header("authorization")) else {
            return fail(key, now: now)
        }
        var match: RemoteDevice?
        for device in devices where RemoteToken.constantTimeEquals(device.token, token) {
            match = device
        }
        guard var device = match else { return fail(key, now: now) }
        if !allowlist.isEmpty {
            guard let login, allowlist.contains(login) else { return fail(key, now: now, status: 403) }
        }
        var changed = false
        if let bound = device.login {
            guard login == bound else { return fail(key, now: now, status: 403) }
        } else if let login {
            device.login = login
            changed = true
        }
        if device.platform == nil {
            device.platform = Self.platform(from: request.header("user-agent"))
            changed = true
        }
        if changed { update(device) }
        limiter.recordSuccess(key)
        lastUsed[device.id] = now
        return .allowed(deviceId: device.id)
    }

    private func fail(_ key: String, now: Date, status: Int = 401) -> AuthResult {
        limiter.recordFailure(key, now: now)
        reject(now: now)
        return .denied(status: status)
    }

    private func reject(now: Date) {
        rejected += 1
        lastRejectedAt = now
        RemoteLog.logger.notice("Rejected a remote access request")
    }

    static func platform(from userAgent: String?) -> String {
        let agent = userAgent ?? ""
        if agent.contains("iPhone") { return "iPhone" }
        if agent.contains("iPad") { return "iPad" }
        if agent.contains("Android") { return "Android" }
        if agent.contains("Macintosh") { return "Mac" }
        if agent.contains("Windows") { return "Windows" }
        if agent.contains("Linux") { return "Linux" }
        return "Browser"
    }
}
