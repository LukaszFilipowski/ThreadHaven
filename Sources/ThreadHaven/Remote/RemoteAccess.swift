import CryptoKit
import Foundation
import Observation

@MainActor
@Observable
final class RemoteAccess {
    enum Phase: Equatable {
        case off
        case starting
        case running(port: UInt16)
    }

    struct Pairing: Equatable {
        var deviceId: String
        var url: String
    }

    private(set) var phase: Phase = .off
    private(set) var problem: String?
    private(set) var probe = Tailscale.Probe()
    private(set) var devices: [RemoteDevice] = []
    private(set) var lastUsed: [String: Date] = [:]
    private(set) var rejectedRequests = 0
    private(set) var pairing: Pairing?
    private(set) var webAppAvailable = false
    private(set) var allowedLogins: [String] = []

    @ObservationIgnored private let store: SessionStore
    @ObservationIgnored private let auth: RemoteAuthenticator
    @ObservationIgnored private let router: RemoteRouter
    @ObservationIgnored private let secrets: RemoteSecretStore
    @ObservationIgnored private let server = HTTPServer()
    @ObservationIgnored private var streams: [ObjectIdentifier: HTTPConnection] = [:]
    @ObservationIgnored private var timers: [Timer] = []
    @ObservationIgnored private var lastSnapshot: [RemoteSessionInfo] = []
    @ObservationIgnored private var lastStatuses: [String: String] = [:]
    @ObservationIgnored private var lastActivity = Date()
    @ObservationIgnored private var vapidKey: P256.Signing.PrivateKey?
    @ObservationIgnored private var attempts = 0

    private var defaults: UserDefaults { .standard }

    init(store: SessionStore, secrets: RemoteSecretStore = KeychainSecretStore()) {
        self.store = store
        self.secrets = secrets
        auth = RemoteAuthenticator(store: secrets)
        router = RemoteRouter(auth: auth)
        router.backend = self
        router.onAuthenticated = { [weak self] _ in self?.markActivity() }
        router.onSubscribe = { [weak self] id, subscription in self?.subscribe(id, subscription) }
        server.onRequest = { [weak self] request, connection in
            Task { @MainActor in self?.handle(request, connection) }
        }
        if let directory = Bundle.main.resourceURL?.appendingPathComponent("Web", isDirectory: true) {
            router.staticFiles = RemoteRouter.loadStaticFiles(from: directory)
        }
        webAppAvailable = router.staticFiles["/"] != nil
        syncDevices()
        if defaults.bool(forKey: Preferences.remoteEnabled) { enable() }
    }

    var isEnabled: Bool { phase != .off }

    var port: UInt16? {
        if case .running(let port) = phase { return port }
        return nil
    }

    var serveCommand: String? { port.map(Tailscale.serveCommand(port:)) }

    func enable() {
        guard phase == .off else { return }
        phase = .starting
        problem = nil
        defaults.set(true, forKey: Preferences.remoteEnabled)
        attempts = 0
        Task { await start(port: savedPort()) }
    }

    func disable(reason: String? = nil) {
        stopTimers()
        server.stop()
        for connection in streams.values { connection.close() }
        streams.removeAll()
        auth.revokeAll()
        pairing = nil
        phase = .off
        problem = reason
        defaults.set(false, forKey: Preferences.remoteEnabled)
        syncDevices()
    }

    func pairDevice() {
        guard isEnabled, let host = probe.dnsName else { return }
        let counter = defaults.integer(forKey: Preferences.remoteDeviceCounter) + 1
        defaults.set(counter, forKey: Preferences.remoteDeviceCounter)
        do {
            let paired = try auth.pair(name: String(localized: "Device \(counter)"))
            pairing = Pairing(deviceId: paired.device.id, url: "https://\(host)/#token=\(paired.token)")
            markActivity()
        } catch {
            problem = error.localizedDescription
        }
        syncDevices()
    }

    func endPairing() {
        pairing = nil
    }

    func revoke(_ id: String) {
        auth.revoke(id)
        if pairing?.deviceId == id { pairing = nil }
        syncDevices()
    }

    func applyAllowlist(_ text: String) {
        auth.allowlist = RemoteAuthenticator.parseAllowlist(text)
        syncDevices()
    }

    func refreshProbe() {
        guard let port else { return }
        Task {
            let probe = await Task.detached(priority: .utility) { Tailscale.probe(port: port) }.value
            apply(probe)
        }
    }

    private var hasSavedPort: Bool {
        (49_152...65_000).contains(defaults.integer(forKey: Preferences.remotePort))
    }

    private func savedPort() -> UInt16 {
        hasSavedPort ? UInt16(defaults.integer(forKey: Preferences.remotePort)) : randomPort()
    }

    var ownLoginMissing: Bool {
        allowedLogins.isEmpty
    }

    var servingWarning: Bool {
        !devices.isEmpty && !probe.serve.served && !probe.funnelUnknown
    }

    private func randomPort() -> UInt16 {
        UInt16.random(in: 49_152...65_000)
    }

    private func start(port: UInt16) async {
        let probe = await Task.detached(priority: .userInitiated) { Tailscale.probe(port: port) }.value
        guard phase == .starting else { return }
        self.probe = probe
        guard probe.cliFound else {
            return fail(String(localized: "Tailscale was not found. Install it and sign in to your tailnet first."))
        }
        guard probe.dnsName != nil else {
            return fail(String(localized: "Tailscale is not connected. Sign in to your tailnet and try again."))
        }
        guard !probe.serve.funneled else {
            return fail(String(localized: "This port is shared with Tailscale Funnel, which would expose it to the internet. Remote access stays off."))
        }
        guard !probe.funnelUnknown else {
            return fail(String(localized: "ThreadHaven could not check Tailscale Funnel for this port, so remote access stays off."))
        }
        auth.ownLogin = probe.login
        loadVAPIDKey()
        server.start(port: port) { [weak self] result in
            Task { @MainActor in self?.listenerChanged(result, port: port) }
        }
    }

    private func listenerChanged(_ result: Result<UInt16, Error>, port: UInt16) {
        switch (result, phase) {
        case (.success(let bound), .starting):
            defaults.set(Int(bound), forKey: Preferences.remotePort)
            phase = .running(port: bound)
            router.allowedHosts = RemoteRouter.allowedHosts(dnsName: probe.dnsName, port: bound)
            auth.allowlist = RemoteAuthenticator.parseAllowlist(defaults.string(forKey: Preferences.remoteAllowlist) ?? "")
            lastActivity = Date()
            lastSnapshot = remoteSessions()
            lastStatuses = Dictionary(lastSnapshot.map { ($0.id, $0.status) }, uniquingKeysWith: { a, _ in a })
            startTimers()
            if auth.devices.isEmpty { pairDevice() }
            refreshProbe()
        case (.failure, .starting) where hasSavedPort:
            defaults.removeObject(forKey: Preferences.remotePort)
            disable(reason: String(localized: "Port \(Int(port)) is used by another app. Remote access was turned off and every device was signed out. Turn it on again to use a new port, then run the new tailscale serve command."))
        case (.failure, .starting) where attempts < 5:
            attempts += 1
            let next = randomPort()
            Task { await start(port: next) }
        case (.failure(let error), .starting), (.failure(let error), .running):
            disable(reason: error.localizedDescription)
        default:
            break
        }
    }

    private func fail(_ message: String) {
        phase = .off
        problem = message
        defaults.set(false, forKey: Preferences.remoteEnabled)
    }

    private func apply(_ probe: Tailscale.Probe) {
        guard isEnabled else { return }
        self.probe = probe
        if probe.serve.funneled {
            disable(reason: String(localized: "Remote access was turned off because Tailscale Funnel exposes its port to the internet."))
        } else if probe.funnelUnknown {
            disable(reason: String(localized: "Remote access was turned off because ThreadHaven could not check Tailscale Funnel."))
        } else if let port {
            auth.ownLogin = probe.login
            syncDevices()
            router.allowedHosts = RemoteRouter.allowedHosts(dnsName: probe.dnsName, port: port)
        }
    }

    private func loadVAPIDKey() {
        if let raw = secrets.loadVAPIDKey(), let key = try? P256.Signing.PrivateKey(rawRepresentation: raw) {
            vapidKey = key
        } else {
            let key = P256.Signing.PrivateKey()
            if (try? secrets.saveVAPIDKey(key.rawRepresentation)) != nil { vapidKey = key }
        }
        router.vapidPublicKey = vapidKey?.publicKey.x963Representation.base64URLEncoded
    }

    private func syncDevices() {
        devices = auth.devices
        lastUsed = auth.lastUsed
        rejectedRequests = auth.rejected
        allowedLogins = auth.effectiveAllowlist
    }

    private func markActivity() {
        lastActivity = Date()
        if pairing.map({ auth.lastUsed[$0.deviceId] != nil }) == true { pairing = nil }
        syncDevices()
    }

    private func startTimers() {
        stopTimers()
        every(1) { $0.broadcastIfChanged() }
        every(25) { $0.ping() }
        every(30) { $0.refreshProbe() }
        every(60) { $0.checkIdle() }
    }

    private func stopTimers() {
        timers.forEach { $0.invalidate() }
        timers.removeAll()
    }

    private func every(_ interval: TimeInterval, _ action: @escaping @MainActor (RemoteAccess) -> Void) {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self { action(self) }
            }
        }
        timer.tolerance = interval * 0.2
        timers.append(timer)
    }

    private func checkIdle() {
        let hours = max(1, defaults.integer(forKey: Preferences.remoteIdleHours))
        if Date().timeIntervalSince(lastActivity) > Double(hours) * 3600 {
            disable(reason: String(localized: "Remote access turned itself off after being idle."))
        }
        syncDevices()
    }

    private func handle(_ request: HTTPRequest, _ connection: HTTPConnection) {
        guard isEnabled else {
            connection.respond(.error(503, "Remote access is off"))
            return
        }
        Task {
            let result = await router.handle(request)
            syncDevices()
            switch result {
            case .response(let response):
                connection.respond(response)
            case .eventStream:
                let id = ObjectIdentifier(connection)
                let opened = connection.beginEventStream(initial: Self.event("sessions", sessionsPayload(lastSnapshot), retry: true)) {
                    Task { @MainActor in self.streams[id] = nil }
                }
                if opened {
                    streams[id] = connection
                } else {
                    connection.respond(.error(503, "Too many open event streams"))
                }
            }
        }
    }

    static func event(_ name: String, _ payload: Data, retry: Bool = false) -> Data {
        var text = retry ? "retry: 5000\n" : ""
        text += "event: \(name)\ndata: "
        var data = Data(text.utf8)
        data.append(payload)
        data.append(Data("\n\n".utf8))
        return data
    }

    private func sessionsPayload(_ sessions: [RemoteSessionInfo]) -> Data {
        HTTPResponse.json(["sessions": sessions.map(\.json)]).body
    }

    private func ping() {
        let data = Data(": ping\n\n".utf8)
        for connection in streams.values { connection.sendEvent(data) }
    }

    private func broadcastIfChanged() {
        let snapshot = remoteSessions()
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        let event = Self.event("sessions", sessionsPayload(snapshot))
        for connection in streams.values { connection.sendEvent(event) }

        for session in snapshot where lastStatuses[session.id] != session.status {
            if session.status == SessionStatus.needsInput.rawValue || session.status == SessionStatus.finished.rawValue,
               lastStatuses[session.id] != nil {
                push(for: session.id)
            }
        }
        lastStatuses = Dictionary(snapshot.map { ($0.id, $0.status) }, uniquingKeysWith: { a, _ in a })
    }

    private func push(for id: String) {
        guard let key = vapidKey, let session = store.session(id) else { return }
        let subject = Self.pushSubject(defaults.string(forKey: Preferences.remotePushContact))
        var body = session.status.label
        if defaults.bool(forKey: Preferences.remotePreviews), let message = session.live?.message, !message.isEmpty {
            body = String(message.prefix(160))
        }
        let payload = (try? JSONSerialization.data(withJSONObject: [
            "title": String(session.title.prefix(80)),
            "body": body,
            "session": id,
        ])) ?? Data()
        for device in auth.devices {
            guard let subscription = device.push,
                  let request = try? WebPush.request(payload: payload, subscription: subscription, vapidKey: key, subject: subject) else { continue }
            let deviceId = device.id
            Task {
                if await WebPush.send(request) == .gone { removeSubscription(deviceId, subscription) }
            }
        }
    }

    nonisolated static let defaultPushSubject = "mailto:push@threadhaven.invalid"

    nonisolated static func pushSubject(_ contact: String?) -> String {
        let trimmed = (contact ?? "").trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 200, !trimmed.contains(" ") else { return defaultPushSubject }
        if trimmed.hasPrefix("mailto:") || trimmed.hasPrefix("https://") { return trimmed }
        if trimmed.contains("@") { return "mailto:" + trimmed }
        return defaultPushSubject
    }

    private func subscribe(_ deviceId: String, _ subscription: PushSubscription) {
        guard var device = auth.device(deviceId) else { return }
        device.push = subscription
        auth.update(device)
        syncDevices()
    }

    private func removeSubscription(_ deviceId: String, _ subscription: PushSubscription) {
        guard var device = auth.device(deviceId), device.push == subscription else { return }
        device.push = nil
        auth.update(device)
        syncDevices()
    }
}

extension RemoteAccess: RemoteBackend {
    func remoteSessions() -> [RemoteSessionInfo] {
        store.sessions.filter { $0.isInteractive }.prefix(60).map { session in
            RemoteSessionInfo(
                id: session.id,
                title: String(session.title.prefix(160)),
                project: session.project,
                status: session.status.rawValue,
                agent: session.agent.rawValue,
                contextPercent: Int((session.contextFraction * 100).rounded()),
                lastActivity: session.lastActivity,
                canSend: TerminalBridge.canSend(to: session) && session.status != .needsInput
            )
        }
    }

    func remoteMessages(_ id: String) async -> [RemoteMessage]? {
        guard let session = store.session(id), remoteSessions().contains(where: { $0.id == id }) else { return nil }
        guard let path = session.meta?.path ?? session.live?.transcriptPath else { return [] }
        let agent = session.agent
        let messages = await Task.detached(priority: .userInitiated) {
            agent == .codex ? CodexReader.recentMessages(path: path, limit: 40) : TranscriptReader.recentMessages(path: path, limit: 40)
        }.value
        return messages.map { RemoteMessage(role: $0.role == .user ? "user" : "assistant", text: $0.text, date: $0.date) }
    }

    func remotePrompt(_ text: String, to id: String, from device: RemoteDevice) -> PromptOutcome {
        guard let session = store.session(id), remoteSessions().contains(where: { $0.id == id }) else { return .unknownSession }
        guard session.status != .needsInput else { return .awaitingApproval }
        guard TerminalBridge.canSend(to: session), store.send(text, to: id) else { return .notSendable }
        Notifier.shared.post(
            sessionId: "remote." + id,
            title: session.title,
            subtitle: String(localized: "Prompt sent from \(device.name)"),
            body: String(text.prefix(180))
        )
        return .sent
    }
}
