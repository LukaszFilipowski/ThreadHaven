import Foundation

enum TranscriptReader {
    static let projectsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects", isDirectory: true)

    struct FileStamp: Sendable, Equatable {
        let modified: Date
        let size: UInt64
    }

    static func stamp(of url: URL) -> FileStamp? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let modified = values.contentModificationDate else { return nil }
        return FileStamp(modified: modified, size: UInt64(values.fileSize ?? 0))
    }

    static func listTranscripts(since: Date) -> [URL: FileStamp] {
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

    static func readMeta(url: URL, stamp: FileStamp) -> TranscriptMeta {
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
                let input = usage["input_tokens"] as? Int ?? 0
                let read = usage["cache_read_input_tokens"] as? Int ?? 0
                let created = usage["cache_creation_input_tokens"] as? Int ?? 0
                meta.contextTokens = input + read + created
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
            if meta.cwd == nil || meta.entrypoint == nil, contains(line, #""cwd":""#), let obj = json(line) {
                if meta.cwd == nil { meta.cwd = obj["cwd"] as? String }
                if meta.entrypoint == nil { meta.entrypoint = obj["entrypoint"] as? String }
            }
            if foundUsage, foundTTL, aiTitle != nil, meta.cwd != nil, meta.entrypoint != nil { break }
        }

        if aiTitle == nil || meta.cwd == nil || meta.firstPrompt == nil {
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
                if aiTitle != nil, meta.cwd != nil, meta.firstPrompt != nil { break }
            }
        }

        meta.title = customTitle ?? aiTitle
        let model = meta.model ?? ""
        meta.contextWindow = (model.contains("[1m]") || meta.contextTokens > 200_000) ? 1_000_000 : 200_000
        return meta
    }

    static func parseDate(_ string: String) -> Date? {
        try? Date(string, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true))
    }

    static func recentMessages(path: String, limit: Int = 60) -> [ChatMessage] {
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
                guard let text = userText(obj), !text.hasPrefix("<") else { continue }
                out.append(ChatMessage(id: id, role: .user, text: String(text.prefix(4000)), date: date))
            } else if let msg = obj["message"] as? [String: Any], let blocks = msg["content"] as? [[String: Any]] {
                let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                out.append(ChatMessage(id: id, role: .assistant, text: String(text.prefix(6000)), date: date))
            }
        }
        return Array(out.suffix(limit))
    }

    static func userText(_ obj: [String: Any]) -> String? {
        guard let msg = obj["message"] as? [String: Any] else { return nil }
        if let s = msg["content"] as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let blocks = msg["content"] as? [[String: Any]] {
            let texts = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            guard !texts.isEmpty else { return nil }
            return texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
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

    private static func contains(_ line: Data, _ needle: String) -> Bool {
        line.range(of: Data(needle.utf8)) != nil
    }

    static func json(_ line: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: line) as? [String: Any]
    }
}
