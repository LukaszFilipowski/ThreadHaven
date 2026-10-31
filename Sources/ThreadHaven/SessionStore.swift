import AppKit
import Observation

@MainActor
@Observable
final class SessionStore {
    private(set) var metas: [String: TranscriptMeta] = [:]
    private(set) var live: [String: LiveInfo] = [:]
    private(set) var aliveTTYs: Set<String> = []
    private(set) var hooksInstalled = HookInstaller.isInstalled
    private(set) var lastError: String?
    private(set) var handoffs: [String: HandoffState] = [:]

    enum HandoffState: Equatable {
        case running
        case failed(String)
    }

    @ObservationIgnored private var stamps: [URL: TranscriptReader.FileStamp] = [:]
    @ObservationIgnored private var eventsOffset: UInt64 = 0
    @ObservationIgnored private var eventsInode: UInt64 = 0
    @ObservationIgnored private var timers: [Timer] = []
    @ObservationIgnored private var scanning = false
    @ObservationIgnored private var lastCompact: [String: Date] = [:]
    @ObservationIgnored private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private var defaults: UserDefaults { .standard }

    init() {
        Preferences.registerDefaults()
        attempt { try HookInstaller.writeScript() }
        Notifier.shared.setup()
        Notifier.shared.onOpen = { [weak self] id in
            MainActor.assumeIsolated { self?.focus(id) }
        }
        readEvents(initial: true)
        refreshProcesses()
        rescan()
        every(1) { $0.readEvents(initial: false) }
        every(4) { $0.refreshProcesses() }
        every(6) { $0.rescan() }
    }

    var sessions: [Session] {
        let showBackground = defaults.bool(forKey: Preferences.showBackground)
        return Set(metas.keys).union(live.keys)
            .compactMap(session)
            .filter { ($0.meta != nil || $0.isLive) && (showBackground || $0.isInteractive) }
            .sorted { a, b in
                a.isLive != b.isLive ? a.isLive : a.lastActivity > b.lastActivity
            }
    }

    func session(_ id: String) -> Session? {
        guard metas[id] != nil || live[id] != nil else { return nil }
        var session = Session(id: id, meta: metas[id], live: live[id])
        if let tty = session.live?.tty { session.processAlive = aliveTTYs.contains(tty) }
        return session
    }

    var attentionCount: Int { sessions.filter(\.needsAttention).count }

    var recentDirectories: [String] {
        var seen = Set<String>()
        return sessions
            .sorted { $0.lastActivity > $1.lastActivity }
            .map(\.cwd)
            .filter { !$0.isEmpty && FileManager.default.fileExists(atPath: $0) && seen.insert($0).inserted }
    }

    func markSeen(_ id: String) {
        guard var info = live[id], !info.seen else { return }
        info.seen = true
        live[id] = info
        Notifier.shared.clear(id)
    }

    func focus(_ id: String) {
        guard let session = session(id) else { return }
        markSeen(id)
        if !TerminalBridge.focus(session) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @discardableResult
    func send(_ text: String, to id: String) -> Bool {
        guard let session = session(id), TerminalBridge.send(text, to: session) else { return false }
        markSeen(id)
        return true
    }

    func compact(_ id: String) {
        if send("/compact", to: id) { lastCompact[id] = Date() }
    }

    func resume(_ id: String) {
        guard let session = session(id), !session.cwd.isEmpty else { return }
        TerminalBridge.openNew(cwd: session.cwd, arguments: ["--resume", id], terminal: Preferences.terminal)
    }

    func newChat(in directory: String, continueLast: Bool, prompt: String) {
        var arguments = continueLast ? ["--continue"] : []
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty { arguments += ["--", prompt] }
        TerminalBridge.openNew(cwd: directory, arguments: arguments, terminal: Preferences.terminal)
    }

    func handOff(_ id: String) {
        guard let session = session(id), !session.cwd.isEmpty,
              let path = session.meta?.path ?? session.live?.transcriptPath,
              handoffs[id] != .running else { return }
        handoffs[id] = .running
        let cwd = session.cwd
        let model = defaults.string(forKey: Preferences.handoffModel) ?? "haiku"
        Task {
            do {
                let digest = await Task.detached(priority: .userInitiated) { Handoff.digest(path: path) }.value
                let note = try await Handoff.summarize(digest: digest, cwd: cwd, model: model)
                let url = try Handoff.save(note: note, sessionId: id, cwd: cwd)
                handoffs[id] = nil
                newChat(in: cwd, continueLast: false, prompt: "Read the handoff note at \(url.path) and continue from its next step.")
            } catch {
                handoffs[id] = .failed(error.localizedDescription)
            }
        }
    }

    func installHooks() {
        attempt { try HookInstaller.install() }
        hooksInstalled = HookInstaller.isInstalled
    }

    func uninstallHooks() {
        attempt { try HookInstaller.uninstall() }
        hooksInstalled = HookInstaller.isInstalled
    }

    private func every(_ interval: TimeInterval, _ action: @escaping @MainActor (SessionStore) -> Void) {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self { action(self) }
            }
        }
        timer.tolerance = interval * 0.3
        timers.append(timer)
    }

    private func attempt(_ work: () throws -> Void) {
        do {
            try work()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func rescan() {
        guard !scanning else { return }
        scanning = true
        let days = Double(max(1, defaults.integer(forKey: Preferences.daysBack)))
        let since = Date().addingTimeInterval(-days * 86_400)
        let known = stamps
        Task {
            let (current, updated) = await Task.detached(priority: .utility) {
                let current = TranscriptReader.listTranscripts(since: since)
                let updated = current
                    .filter { known[$0.key] != $0.value }
                    .map { TranscriptReader.readMeta(url: $0.key, stamp: $0.value) }
                return (current, updated)
            }.value
            for url in Set(stamps.keys).subtracting(current.keys) {
                metas[url.deletingPathExtension().lastPathComponent] = nil
            }
            stamps = current
            for meta in updated { metas[meta.sessionId] = meta }
            scanning = false
        }
    }

    private func reloadMeta(_ id: String) {
        guard let path = metas[id]?.path ?? live[id]?.transcriptPath else { return }
        let url = URL(fileURLWithPath: path)
        Task {
            let result = await Task.detached(priority: .utility) { () -> (TranscriptReader.FileStamp, TranscriptMeta)? in
                guard let stamp = TranscriptReader.stamp(of: url) else { return nil }
                return (stamp, TranscriptReader.readMeta(url: url, stamp: stamp))
            }.value
            guard let (stamp, meta) = result else { return }
            stamps[url] = stamp
            metas[meta.sessionId] = meta
            autoCompactIfNeeded(id)
        }
    }

    private func refreshProcesses() {
        Task {
            let ttys = await Task.detached(priority: .utility) { ProcessScanner.claudeTTYs() }.value
            if aliveTTYs != ttys { aliveTTYs = ttys }
        }
    }

    private func readEvents(initial: Bool) {
        let path = HookInstaller.eventsURL.path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attrs[.size] as? NSNumber)?.uint64Value else { return }
        let inode = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        if inode != eventsInode || size < eventsOffset {
            eventsInode = inode
            eventsOffset = 0
        }
        if initial && size > 2_000_000 { eventsOffset = size - 2_000_000 }
        guard size > eventsOffset, let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: eventsOffset)
        guard let data = try? handle.readToEnd(), let lastNewline = data.lastIndex(of: 0x0A) else { return }

        let complete = data[...lastNewline]
        eventsOffset += UInt64(complete.count)
        for line in complete.split(separator: 0x0A) {
            if let event = try? decoder.decode(HookLine.self, from: Data(line)) {
                apply(event, notify: !initial)
            }
        }
    }

    private static let approvalNotifications: Set<String?> = ["permission_prompt", "elicitation_dialog", nil]

    private func endOtherSessions(on tty: String?, except id: String) {
        guard let tty, tty != "??" else { return }
        for (otherId, var other) in live where otherId != id && other.tty == tty && !other.ended {
            other.ended = true
            live[otherId] = other
            Notifier.shared.clear(otherId)
        }
    }

    private func apply(_ line: HookLine, notify: Bool) {
        let event = line.event
        let id = event.sessionId
        var info = live[id] ?? LiveInfo(updatedAt: .distantPast)
        info.merge(line)

        var alert: String?
        switch event.hookEventName {
        case "SessionStart":
            info.ended = false
            if info.status != .working { info.status = .idle }
            endOtherSessions(on: info.tty, except: id)
        case "UserPromptSubmit":
            info.ended = false
            info.markWorking()
            endOtherSessions(on: info.tty, except: id)
        case "PostToolUse":
            if info.status == .needsInput { info.markWorking() }
        case "Notification" where event.notificationType == "idle_prompt":
            if info.status == .working { info.status = .finished }
        case "Notification" where Self.approvalNotifications.contains(event.notificationType):
            info.status = .needsInput
            info.message = event.message
            info.seen = false
            alert = event.message ?? String(localized: "Claude needs your attention")
        case "Stop":
            info.status = .finished
            info.message = event.lastAssistantMessage.map { String($0.prefix(300)) }
            info.seen = false
            alert = event.lastAssistantMessage.map { String($0.prefix(180)) }
                ?? String(localized: "Claude finished and is waiting for you")
        case "SessionEnd":
            info.ended = true
            info.status = .idle
        default:
            break
        }
        live[id] = info
        if info.seen || info.ended { Notifier.shared.clear(id) }

        guard notify else { return }
        if metas[id] == nil || ["Stop", "SessionStart"].contains(event.hookEventName) {
            reloadMeta(id)
        }
        if let alert, defaults.bool(forKey: Preferences.notify),
           info.isInteractive || defaults.bool(forKey: Preferences.showBackground) {
            let title = session(id)?.title ?? "Claude"
            Notifier.shared.post(sessionId: id, title: title, subtitle: info.status.label, body: alert)
        }
    }

    private func autoCompactIfNeeded(_ id: String) {
        guard defaults.bool(forKey: Preferences.autoCompact),
              let session = session(id), session.status == .finished,
              TerminalBridge.canSend(to: session),
              let tokens = session.meta?.contextTokens,
              tokens >= defaults.integer(forKey: Preferences.compactTokens),
              Date().timeIntervalSince(lastCompact[id] ?? .distantPast) > 600 else { return }
        compact(id)
        Notifier.shared.post(
            sessionId: id + ".compact",
            title: session.title,
            subtitle: String(localized: "Auto-compact started"),
            body: String(localized: "Context reached \(ContextGauge.short(tokens)) tokens")
        )
    }
}
