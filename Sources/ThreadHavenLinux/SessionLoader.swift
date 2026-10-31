import Foundation
import ThreadHavenCore

nonisolated struct SessionRow: Identifiable, Sendable {
    let meta: TranscriptMeta

    var id: String { meta.path }

    var title: String {
        if let title = meta.title, !title.isEmpty { return title }
        if let prompt = meta.firstPrompt, !prompt.isEmpty { return String(prompt.prefix(80)) }
        return project
    }

    var project: String {
        guard let cwd = meta.cwd, !cwd.isEmpty else { return "Unknown folder" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    var contextPercent: Int {
        guard meta.contextWindow > 0 else { return 0 }
        return min(100, meta.contextTokens * 100 / meta.contextWindow)
    }

    var subtitle: String {
        "\(meta.agent.name) · \(project) · \(contextPercent)% context"
    }
}

nonisolated struct SessionDetail: Sendable {
    var sessionId = ""
    var messages: [ChatMessage] = []
    var stats: TokenStats?
}

nonisolated struct StatItem: Identifiable, Sendable {
    let label: String
    let value: String

    var id: String { label }
}

nonisolated enum SessionLoader {
    static let days = 14
    static let messageLimit = 30
    static let messageLength = 2_000

    static func recentSessions(now: Date = Date()) -> [SessionRow] {
        let since = now.addingTimeInterval(-Double(days) * 86_400)
        let claude = TranscriptReader.listTranscripts(since: since).map { TranscriptReader.readMeta(url: $0.key, stamp: $0.value) }
        let codex = CodexReader.listSessions(since: since).map { CodexReader.readMeta(url: $0.key, stamp: $0.value) }
        return (claude + codex)
            .filter { ($0.entrypoint ?? "cli") == "cli" }
            .sorted { $0.modified > $1.modified }
            .map(SessionRow.init)
    }

    static func detail(for meta: TranscriptMeta) -> SessionDetail {
        switch meta.agent {
        case .claude:
            SessionDetail(
                sessionId: meta.path,
                messages: trimmed(TranscriptReader.recentMessages(path: meta.path, limit: messageLimit)),
                stats: TokenStats.analyze(url: URL(fileURLWithPath: meta.path))
            )
        case .codex:
            SessionDetail(
                sessionId: meta.path,
                messages: trimmed(CodexReader.recentMessages(path: meta.path, limit: messageLimit))
            )
        }
    }

    static func statItems(_ stats: TokenStats) -> [StatItem] {
        [
            StatItem(label: "Context", value: tokens(stats.currentContext)),
            StatItem(label: "Peak", value: tokens(stats.peakContext)),
            StatItem(label: "Start-up", value: tokens(stats.baselineContext)),
            StatItem(label: "Replies", value: "\(stats.turns)"),
            StatItem(label: "Cache read", value: tokens(stats.cacheReadTokens)),
            StatItem(label: "Cache write", value: tokens(stats.cacheWriteTokens)),
            StatItem(label: "Output", value: tokens(stats.outputTokens)),
            StatItem(label: "Cold rebuilds", value: "\(stats.coldRebuilds) · \(tokens(stats.coldRebuildTokens))"),
        ]
    }

    static func tokens(_ count: Int) -> String {
        switch count {
        case 1_000_000...: String(format: "%.1fM", Double(count) / 1_000_000)
        case 1_000...: "\(count / 1_000)k"
        default: "\(count)"
        }
    }

    private static func trimmed(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.map { message in
            guard message.text.count > messageLength else { return message }
            return ChatMessage(id: message.id, role: message.role, text: String(message.text.prefix(messageLength)) + "…", date: message.date)
        }
    }
}

nonisolated final class Mailbox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?

    func put(_ newValue: Value) {
        lock.withLock { value = newValue }
    }

    func take() -> Value? {
        lock.withLock {
            defer { value = nil }
            return value
        }
    }
}
