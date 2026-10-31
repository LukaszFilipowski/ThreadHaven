import Foundation

enum SessionStatus: String, Sendable {
    case working
    case needsInput
    case finished
    case idle
    case closed

    var label: String {
        switch self {
        case .working: String(localized: "Working…")
        case .needsInput: String(localized: "Needs your approval")
        case .finished: String(localized: "Your turn")
        case .idle: String(localized: "Idle")
        case .closed: String(localized: "Not running")
        }
    }

    var symbol: String {
        switch self {
        case .working: "circle.dotted.circle"
        case .needsInput: "exclamationmark.bubble.fill"
        case .finished: "checkmark.circle.fill"
        case .idle: "circle"
        case .closed: "moon.zzz"
        }
    }
}

struct TranscriptMeta: Sendable {
    var sessionId: String
    var path: String
    var cwd: String?
    var title: String?
    var firstPrompt: String?
    var lastPrompt: String?
    var model: String?
    var contextTokens: Int = 0
    var contextWindow: Int = 200_000
    var lastReplyAt: Date?
    var cacheTTL: TimeInterval = 300
    var entrypoint: String?
    var modified: Date
    var size: UInt64
}

struct LiveInfo: Sendable {
    var status: SessionStatus = .idle
    var message: String?
    var tty: String?
    var term: String?
    var bundle: String?
    var cwd: String?
    var transcriptPath: String?
    var seen = true
    var ended = false
    var updatedAt: Date

    var isInteractive: Bool { (tty ?? "??") != "??" }

    mutating func merge(_ line: HookLine) {
        let event = line.event
        if let v = event.cwd, !v.isEmpty { cwd = v }
        if let v = event.transcriptPath, !v.isEmpty { transcriptPath = v }
        if let v = line.term, !v.isEmpty { term = v }
        if let v = line.bundle, !v.isEmpty { bundle = v }
        if let v = line.tty, !v.isEmpty { tty = v }
        updatedAt = Date(timeIntervalSince1970: line.ts)
    }

    mutating func markWorking() {
        status = .working
        message = nil
        seen = true
    }
}

struct Session: Identifiable, Sendable {
    let id: String
    var meta: TranscriptMeta?
    var live: LiveInfo?
    var processAlive = false

    var cwd: String { meta?.cwd ?? live?.cwd ?? "" }

    var project: String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? String(localized: "Unknown") : name
    }

    var title: String {
        if let t = meta?.title, !t.isEmpty { return t }
        if let p = meta?.firstPrompt, !p.isEmpty { return String(p.prefix(80)) }
        return project
    }

    var isLive: Bool {
        guard let live, !live.ended, live.isInteractive else { return false }
        return processAlive
    }

    var isInteractive: Bool {
        if let entrypoint = meta?.entrypoint { return entrypoint == "cli" }
        return live?.isInteractive ?? true
    }

    var status: SessionStatus { isLive ? (live?.status ?? .idle) : .closed }

    var needsAttention: Bool {
        guard isLive, let live, !live.seen else { return false }
        return live.status == .needsInput || live.status == .finished
    }

    var lastActivity: Date {
        max(meta?.modified ?? .distantPast, live?.updatedAt ?? .distantPast)
    }

    var contextFraction: Double {
        guard let meta, meta.contextWindow > 0 else { return 0 }
        return min(1, Double(meta.contextTokens) / Double(meta.contextWindow))
    }

    var cacheExpiresAt: Date? {
        guard let meta, let last = meta.lastReplyAt else { return nil }
        return last.addingTimeInterval(meta.cacheTTL)
    }

    func isCacheCold(at date: Date = .now) -> Bool {
        guard let expires = cacheExpiresAt else { return false }
        return date > expires
    }

    var terminalBundle: String? {
        if let bundle = live?.bundle, TerminalBridge.knownBundles.contains(bundle) { return bundle }
        return TerminalBridge.bundle(forTermProgram: live?.term)
    }
}

struct ChatMessage: Identifiable, Sendable {
    enum Role: Sendable { case user, assistant }
    let id: String
    let role: Role
    let text: String
    let date: Date?
}

struct HookLine: Decodable {
    let ts: Double
    let term: String?
    let bundle: String?
    let tty: String?
    let event: HookEvent
}

struct HookEvent: Decodable {
    let sessionId: String
    let hookEventName: String
    let cwd: String?
    let transcriptPath: String?
    let message: String?
    let notificationType: String?
    let lastAssistantMessage: String?
}
