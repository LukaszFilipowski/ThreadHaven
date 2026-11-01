import Foundation

public enum TranscriptReader {
    public static let projectsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects", isDirectory: true)

    public struct FileStamp: Sendable, Equatable {
        public let modified: Date
        public let size: UInt64
    }

    public static func stamp(of url: URL) -> FileStamp? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let modified = values.contentModificationDate else { return nil }
        return FileStamp(modified: modified, size: UInt64(values.fileSize ?? 0))
    }

    public static func listTranscripts(since: Date) -> [URL: FileStamp] {
        let fm = FileManager.default
        var result: [URL: FileStamp] = [:]
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]
        guard let dirs = try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: keys) else { return result }
        for dir in dirs {
            guard let v = try? dir.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey]),
                  v.isDirectory == true else { continue }
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                if let stamp = stamp(of: file), stamp.modified >= since { result[file] = stamp }
            }
        }
        return result
    }

    public static func readMeta(url: URL, stamp: FileStamp) -> TranscriptMeta {
        var meta = TranscriptMeta(
            sessionId: url.deletingPathExtension().lastPathComponent,
            path: url.path,
            modified: stamp.modified,
            size: stamp.size
        )
        var customTitle: String?
        var aiTitle: String?
        var foundUsage = false
        var foundTTL = false

        let tail = readChunk(url: url, fromEnd: true, bytes: 1_000_000)
        for line in lines(tail).reversed() {
            if !foundUsage, contains(line, #""type":"assistant""#), let obj = json(line),
               obj["isSidechain"] as? Bool != true,
               let msg = obj["message"] as? [String: Any], let usage = msg["usage"] as? [String: Any] {
                meta.contextTokens = context(of: usage)
                meta.model = (obj["requestedModel"] as? String) ?? (msg["model"] as? String)
                meta.lastReplyAt = (obj["timestamp"] as? String).flatMap(parseDate)
                foundUsage = true
                if meta.cwd == nil { meta.cwd = obj["cwd"] as? String }
                if meta.entrypoint == nil { meta.entrypoint = obj["entrypoint"] as? String }
            }
            if !foundTTL, contains(line, #""ephemeral_"#), let obj = json(line),
               let usage = (obj["message"] as? [String: Any])?["usage"] as? [String: Any],
               let creation = usage["cache_creation"] as? [String: Any] {
                if (creation["ephemeral_1h_input_tokens"] as? Int ?? 0) > 0 {
                    meta.cacheTTL = 3600
                    foundTTL = true
                } else if (creation["ephemeral_5m_input_tokens"] as? Int ?? 0) > 0 {
                    meta.cacheTTL = 300
                    foundTTL = true
                }
            }
            if customTitle == nil, contains(line, #""custom-title""#), let obj = json(line) {
                customTitle = obj["customTitle"] as? String ?? obj["title"] as? String
            }
            if aiTitle == nil, contains(line, #""ai-title""#), let obj = json(line) {
                aiTitle = obj["aiTitle"] as? String
            }
            if meta.lastPrompt == nil, contains(line, #""last-prompt""#), let obj = json(line) {
                meta.lastPrompt = obj["lastPrompt"] as? String
            }
            if meta.cwd == nil || meta.entrypoint == nil || meta.gitBranch == nil, contains(line, #""cwd":""#), let obj = json(line) {
                if meta.cwd == nil { meta.cwd = obj["cwd"] as? String }
                if meta.entrypoint == nil { meta.entrypoint = obj["entrypoint"] as? String }
                if meta.gitBranch == nil, let branch = obj["gitBranch"] as? String, !branch.isEmpty { meta.gitBranch = branch }
            }
            if foundUsage, foundTTL, aiTitle != nil, meta.cwd != nil, meta.entrypoint != nil { break }
        }

        if aiTitle == nil || meta.cwd == nil || meta.firstPrompt == nil || meta.baselineContext == nil {
            let head = stamp.size > 1_000_000 ? readChunk(url: url, fromEnd: false, bytes: 300_000) : tail
            for line in lines(head) {
                if aiTitle == nil, contains(line, #""ai-title""#), let obj = json(line) {
                    aiTitle = obj["aiTitle"] as? String
                }
                if contains(line, #""type":"user""#), let obj = json(line) {
                    if meta.cwd == nil { meta.cwd = obj["cwd"] as? String }
                    if meta.entrypoint == nil { meta.entrypoint = obj["entrypoint"] as? String }
                    if meta.firstPrompt == nil, obj["isMeta"] as? Bool != true,
                       let text = userText(obj), !text.hasPrefix("<") {
                        meta.firstPrompt = text.replacingOccurrences(of: "\n", with: " ")
                    }
                }
                if meta.baselineContext == nil, contains(line, #""type":"assistant""#), let obj = json(line),
                   obj["isSidechain"] as? Bool != true,
                   let usage = (obj["message"] as? [String: Any])?["usage"] as? [String: Any] {
                    meta.baselineContext = context(of: usage)
                }
                if aiTitle != nil, meta.cwd != nil, meta.firstPrompt != nil, meta.baselineContext != nil { break }
            }
        }

        meta.title = customTitle ?? aiTitle
        let model = meta.model ?? ""
        meta.contextWindow = (model.contains("[1m]") || meta.contextTokens > 200_000) ? 1_000_000 : 200_000
        return meta
    }

    private static func context(of usage: [String: Any]) -> Int {
        ["input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"]
            .map { usage[$0] as? Int ?? 0 }
            .reduce(0, +)
    }

    public static func parseDate(_ string: String) -> Date? {
        try? Date(string, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true))
    }

    public static func looksInteractive(_ url: URL) -> Bool {
        let head = readChunk(url: url, fromEnd: false, bytes: 64_000)
        let background = head.range(of: Data(#""entrypoint":"sdk-"#.utf8)) != nil
        return !background || head.range(of: Data(#""entrypoint":"cli""#.utf8)) != nil
    }

    public static func recentMessages(path: String, limit: Int = 60) -> [ChatMessage] {
        let url = URL(fileURLWithPath: path)
        let chunk = readChunk(url: url, fromEnd: true, bytes: 3_000_000)
        var out: [ChatMessage] = []
        for line in lines(chunk) {
            let isUser = contains(line, #""type":"user""#)
            let isAssistant = contains(line, #""type":"assistant""#)
            guard isUser || isAssistant, let obj = json(line) else { continue }
            if obj["isSidechain"] as? Bool == true || obj["isMeta"] as? Bool == true { continue }
            let id = obj["uuid"] as? String ?? UUID().uuidString
            let date = (obj["timestamp"] as? String).flatMap(parseDate)
            if isUser {
                if let raw = rawUserText(obj), let command = commandMessage(raw, id: id, date: date) {
                    out.append(command)
                    continue
                }
                guard let text = userText(obj), !text.isEmpty else { continue }
                out.append(ChatMessage(id: id, role: .user, text: String(text.prefix(4000)), date: date))
            } else if let msg = obj["message"] as? [String: Any], let blocks = msg["content"] as? [[String: Any]] {
                for (index, block) in blocks.enumerated() {
                    let blockID = "\(id)-\(index)"
                    switch block["type"] as? String {
                    case "text":
                        let text = (block["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty {
                            out.append(ChatMessage(id: blockID, role: .assistant, text: String(text.prefix(12000)), date: date))
                        }
                    case "tool_use":
                        out.append(ChatMessage(id: blockID, role: .tool, text: toolSummary(block), date: date))
                    default:
                        break
                    }
                }
            }
        }
        return Array(out.suffix(limit))
    }

    static func userText(_ obj: [String: Any]) -> String? {
        guard let raw = rawUserText(obj) else { return nil }
        let text = withoutTaggedBlocks(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    static func rawUserText(_ obj: [String: Any]) -> String? {
        guard let msg = obj["message"] as? [String: Any] else { return nil }
        if let s = msg["content"] as? String { return s }
        guard let blocks = msg["content"] as? [[String: Any]] else { return nil }
        let texts = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }

    static func commandMessage(_ raw: String, id: String, date: Date?) -> ChatMessage? {
        if let name = tagContent("command-name", in: raw) {
            let arguments = tagContent("command-args", in: raw) ?? ""
            let text = [name, arguments].filter { !$0.isEmpty }.joined(separator: " ")
            return ChatMessage(id: id, role: .user, text: text, date: date)
        }
        for tag in ["local-command-stdout", "local-command-stderr"] {
            if let output = tagContent(tag, in: raw), !output.isEmpty {
                return ChatMessage(id: id, role: .output, text: String(output.prefix(6000)), date: date)
            }
        }
        return nil
    }

    static func tagContent(_ tag: String, in text: String) -> String? {
        guard let start = text.range(of: "<\(tag)>"), let end = text.range(of: "</\(tag)>", range: start.upperBound..<text.endIndex) else { return nil }
        return String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let taggedBlock = try! NSRegularExpression(pattern: "<([a-zA-Z][a-zA-Z0-9_-]*)(\\s[^>]*)?>[\\s\\S]*?</\\1>")

    static func withoutTaggedBlocks(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return taggedBlock.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    static func toolSummary(_ block: [String: Any]) -> String {
        let name = block["name"] as? String ?? "Tool"
        let input = block["input"] as? [String: Any] ?? [:]
        let keys = ["description", "command", "file_path", "pattern", "path", "url", "query", "prompt"]
        guard let detail = keys.lazy.compactMap({ input[$0] as? String }).first(where: { !$0.isEmpty }) else { return name }
        let line = detail.prefix { !$0.isNewline }
        return "\(name) · \(line.count > 140 ? line.prefix(139) + "…" : line)"
    }

    static func readChunk(url: URL, fromEnd: Bool, bytes: UInt64) -> Data {
        guard let h = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        if fromEnd {
            let start = size > bytes ? size - bytes : 0
            try? h.seek(toOffset: start)
            return (try? h.readToEnd()) ?? Data()
        }
        try? h.seek(toOffset: 0)
        return (try? h.read(upToCount: Int(min(bytes, size)))) ?? Data()
    }

    static func lines(_ data: Data) -> [Data] {
        data.split(separator: 0x0A).map { Data($0) }
    }

    static func contains(_ line: Data, _ needle: String) -> Bool {
        line.range(of: Data(needle.utf8)) != nil
    }

    static func json(_ line: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: line) as? [String: Any]
    }
}
