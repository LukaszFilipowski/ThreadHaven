import Foundation

public enum Agent: String, Sendable {
    case claude
    case codex

    public var name: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    public var command: String { rawValue }

    public var canCompact: Bool { self == .claude }

    public func resumeArguments(_ sessionId: String) -> [String] {
        switch self {
        case .claude: ["--resume", sessionId]
        case .codex: ["resume", sessionId]
        }
    }
}

public struct TranscriptMeta: Sendable {
    public var agent: Agent
    public var sessionId: String
    public var path: String
    public var cwd: String?
    public var title: String?
    public var firstPrompt: String?
    public var lastPrompt: String?
    public var model: String?
    public var contextTokens: Int
    public var baselineContext: Int?
    public var contextWindow: Int
    public var lastReplyAt: Date?
    public var cacheTTL: TimeInterval
    public var entrypoint: String?
    public var gitBranch: String?
    public var modified: Date
    public var size: UInt64

    public init(
        agent: Agent = .claude,
        sessionId: String,
        path: String,
        cwd: String? = nil,
        title: String? = nil,
        firstPrompt: String? = nil,
        lastPrompt: String? = nil,
        model: String? = nil,
        contextTokens: Int = 0,
        baselineContext: Int? = nil,
        contextWindow: Int = 200_000,
        lastReplyAt: Date? = nil,
        cacheTTL: TimeInterval = 300,
        entrypoint: String? = nil,
        gitBranch: String? = nil,
        modified: Date,
        size: UInt64
    ) {
        self.agent = agent
        self.sessionId = sessionId
        self.path = path
        self.cwd = cwd
        self.title = title
        self.firstPrompt = firstPrompt
        self.lastPrompt = lastPrompt
        self.model = model
        self.contextTokens = contextTokens
        self.baselineContext = baselineContext
        self.contextWindow = contextWindow
        self.lastReplyAt = lastReplyAt
        self.cacheTTL = cacheTTL
        self.entrypoint = entrypoint
        self.gitBranch = gitBranch
        self.modified = modified
        self.size = size
    }
}

public struct ChatMessage: Identifiable, Sendable {
    public enum Role: Sendable { case user, assistant, tool, output }
    public let id: String
    public let role: Role
    public let text: String
    public let date: Date?

    public init(id: String, role: Role, text: String, date: Date?) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
    }
}
