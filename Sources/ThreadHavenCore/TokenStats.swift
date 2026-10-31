import Foundation

public struct TokenStats: Sendable, Equatable {
    public struct ToolResult: Sendable, Equatable {
        public let tool: String
        public let label: String?
        public let tokens: Int
    }

    public static let coldRebuildMinimumTokens = 20_000
    public static let coldRebuildContextShare = 0.5
    public static let heaviestToolResultLimit = 5
    public static let bytesPerToken = 4

    public var turns = 0
    public var baselineContext = 0
    public var currentContext = 0
    public var peakContext = 0
    public var cacheReadTokens = 0
    public var cacheWriteTokens = 0
    public var outputTokens = 0
    public var coldRebuilds = 0
    public var coldRebuildTokens = 0
    public var heaviestToolResults: [ToolResult] = []
    public var lastReply: Date?
    public var contexts: [Int] = []

    public init() {}

    public static func analyze(url: URL) -> TokenStats {
        var tally = Tally()
        forEachLine(of: url) { line in
            withAutoreleasePool { tally.consume(line) }
        }
        return tally.finish()
    }

    private static func forEachLine(of url: URL, chunkSize: Int = 4 << 20, _ body: (Data) -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        var buffer = Data()
        var reachedEnd = false
        while !reachedEnd {
            withAutoreleasePool {
                guard let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty else {
                    reachedEnd = true
                    return
                }
                buffer.append(chunk)
                var start = buffer.startIndex
                while let end = buffer[start...].firstIndex(of: 0x0A) {
                    if end > start { body(buffer[start..<end]) }
                    start = buffer.index(after: end)
                }
                buffer = Data(buffer[start...])
            }
        }
        if !buffer.isEmpty { body(buffer) }
    }
}

private struct Tally {
    private struct ToolUse {
        let name: String
        let label: String?
    }

    private static let assistantMarker = Data(#""type":"assistant""#.utf8)
    private static let toolResultMarker = Data(#""type":"tool_result""#.utf8)

    private var stats = TokenStats()
    private var seenMessages: Set<String> = []
    private var toolUses: [String: ToolUse] = [:]
    private var lastTimestamp: String?

    mutating func consume(_ line: Data) {
        if line.range(of: Self.assistantMarker) != nil {
            guard let obj = mainThreadObject(line), obj["type"] as? String == "assistant" else { return }
            consumeAssistant(obj)
        } else if line.range(of: Self.toolResultMarker) != nil {
            guard let obj = mainThreadObject(line), obj["type"] as? String == "user" else { return }
            consumeToolResults(obj)
        }
    }

    func finish() -> TokenStats {
        var result = stats
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        result.lastReply = lastTimestamp.flatMap { iso.date(from: $0) }
        return result
    }

    private func mainThreadObject(_ line: Data) -> [String: Any]? {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              obj["isSidechain"] as? Bool != true else { return nil }
        return obj
    }

    private mutating func consumeAssistant(_ obj: [String: Any]) {
        guard let message = obj["message"] as? [String: Any] else { return }
        for block in message["content"] as? [[String: Any]] ?? [] where block["type"] as? String == "tool_use" {
            guard let id = block["id"] as? String else { continue }
            let input = block["input"] as? [String: Any] ?? [:]
            toolUses[id] = ToolUse(name: block["name"] as? String ?? "?", label: Self.label(for: input))
        }
        guard let id = message["id"] as? String, let usage = message["usage"] as? [String: Any],
              seenMessages.insert(id).inserted else { return }
        lastTimestamp = obj["timestamp"] as? String ?? lastTimestamp
        record(
            input: usage["input_tokens"] as? Int ?? 0,
            cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0,
            cacheWrite: usage["cache_creation_input_tokens"] as? Int ?? 0,
            output: usage["output_tokens"] as? Int ?? 0
        )
    }

    private mutating func record(input: Int, cacheRead: Int, cacheWrite: Int, output: Int) {
        let context = input + cacheRead + cacheWrite
        if stats.turns == 0 {
            stats.baselineContext = context
        } else if cacheWrite > TokenStats.coldRebuildMinimumTokens,
                  Double(cacheWrite) > Double(context) * TokenStats.coldRebuildContextShare {
            stats.coldRebuilds += 1
            stats.coldRebuildTokens += cacheWrite
        }
        stats.turns += 1
        stats.currentContext = context
        stats.contexts.append(context)
        stats.peakContext = max(stats.peakContext, context)
        stats.cacheReadTokens += cacheRead
        stats.cacheWriteTokens += cacheWrite
        stats.outputTokens += output
    }

    private mutating func consumeToolResults(_ obj: [String: Any]) {
        guard let message = obj["message"] as? [String: Any],
              let blocks = message["content"] as? [[String: Any]] else { return }
        for block in blocks where block["type"] as? String == "tool_result" {
            guard let id = block["tool_use_id"] as? String else { continue }
            let use = toolUses.removeValue(forKey: id)
            let tokens = Self.byteCount(of: block["content"]) / TokenStats.bytesPerToken
            insert(TokenStats.ToolResult(tool: use?.name ?? "?", label: use?.label, tokens: tokens))
        }
    }

    private mutating func insert(_ result: TokenStats.ToolResult) {
        let limit = TokenStats.heaviestToolResultLimit
        guard stats.heaviestToolResults.count < limit
                || result.tokens > stats.heaviestToolResults.last?.tokens ?? 0 else { return }
        stats.heaviestToolResults.append(result)
        stats.heaviestToolResults.sort { $0.tokens > $1.tokens }
        stats.heaviestToolResults = Array(stats.heaviestToolResults.prefix(limit))
    }

    private static func byteCount(of content: Any?) -> Int {
        if let text = content as? String { return text.utf8.count }
        guard let blocks = content as? [[String: Any]] else { return 0 }
        return blocks.reduce(0) { $0 + (($1["text"] as? String)?.utf8.count ?? 0) }
    }

    private static func label(for input: [String: Any]) -> String? {
        let keys = ["file_path", "notebook_path", "path", "command", "pattern", "url", "query", "description"]
        guard let value = keys.lazy.compactMap({ input[$0] as? String }).first(where: { !$0.isEmpty }) else { return nil }
        let firstLine = value.prefix { !$0.isNewline }
        return firstLine.count > 80 ? firstLine.prefix(79) + "…" : String(firstLine)
    }
}
