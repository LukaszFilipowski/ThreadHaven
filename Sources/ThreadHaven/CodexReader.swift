import Foundation

enum CodexReader {
    static let sessionsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions", isDirectory: true)

    static func listSessions(since: Date, in root: URL = sessionsDir) -> [URL: TranscriptReader.FileStamp] {
        var result: [URL: TranscriptReader.FileStamp] = [:]
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: .skipsHiddenFiles) else {
            return result
        }
        for case let file as URL in files where isRollout(file) {
            if let stamp = TranscriptReader.stamp(of: file), stamp.modified >= since { result[file] = stamp }
        }
        return result
    }

    static func isRollout(_ url: URL) -> Bool {
        url.pathExtension == "jsonl" && url.lastPathComponent.hasPrefix("rollout-")
    }

    static func readMeta(url: URL, stamp: TranscriptReader.FileStamp) -> TranscriptMeta {
        var meta = TranscriptMeta(
            agent: .codex,
            sessionId: sessionId(fromFileName: url),
            path: url.path,
            modified: stamp.modified,
            size: stamp.size
        )
        var foundUsage = false

        let tail = TranscriptReader.readChunk(url: url, fromEnd: true, bytes: 1_000_000)
        for line in TranscriptReader.lines(tail).reversed() {
            if !foundUsage, let payload = payload(line, type: "event_msg", marker: "token_count"),
               let info = payload["info"] as? [String: Any] {
                let usage = info["last_token_usage"] as? [String: Any] ?? [:]
                meta.contextTokens = usage["total_tokens"] as? Int ?? 0
                if let window = info["model_context_window"] as? Int, window > 0 { meta.contextWindow = window }
                foundUsage = true
            }
            if meta.model == nil, let payload = payload(line, type: "turn_context") {
                meta.model = payload["model"] as? String
            }
            if meta.lastPrompt == nil, let payload = payload(line, type: "response_item"), let text = prompt(payload) {
                meta.lastPrompt = text
            }
            if foundUsage, meta.model != nil, meta.lastPrompt != nil { break }
        }

        let head = stamp.size > 1_000_000 ? TranscriptReader.readChunk(url: url, fromEnd: false, bytes: 300_000) : tail
        for line in TranscriptReader.lines(head) {
            if let payload = payload(line, type: "session_meta") {
                if let id = payload["id"] as? String, !id.isEmpty { meta.sessionId = id }
                meta.cwd = payload["cwd"] as? String
                meta.entrypoint = entrypoint(payload)
            }
            if meta.cwd == nil, let payload = payload(line, type: "turn_context") {
                meta.cwd = payload["cwd"] as? String
            }
            if meta.firstPrompt == nil, let payload = payload(line, type: "response_item"), let text = prompt(payload) {
                meta.firstPrompt = text.replacingOccurrences(of: "\n", with: " ")
            }
            if meta.entrypoint != nil, meta.firstPrompt != nil { break }
        }
        return meta
    }

    static func recentMessages(path: String, limit: Int = 60) -> [ChatMessage] {
        let chunk = TranscriptReader.readChunk(url: URL(fileURLWithPath: path), fromEnd: true, bytes: 3_000_000)
        var out: [ChatMessage] = []
        for line in TranscriptReader.lines(chunk) {
            guard let obj = TranscriptReader.json(line), obj["type"] as? String == "response_item",
                  let payload = obj["payload"] as? [String: Any] else { continue }
            let id = payload["id"] as? String ?? UUID().uuidString
            let date = (obj["timestamp"] as? String).flatMap(TranscriptReader.parseDate)
            if let text = prompt(payload) {
                out.append(ChatMessage(id: id, role: .user, text: String(text.prefix(4000)), date: date))
            } else if isMessage(payload, role: "assistant") {
                let text = texts(payload).joined(separator: "\n")
                guard !text.isEmpty else { continue }
                out.append(ChatMessage(id: id, role: .assistant, text: String(text.prefix(6000)), date: date))
            }
        }
        return Array(out.suffix(limit))
    }

    static func prompt(_ payload: [String: Any]) -> String? {
        guard isMessage(payload, role: "user") else { return nil }
        let text = texts(payload).filter { !$0.hasPrefix("<") }.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    private static func isMessage(_ payload: [String: Any], role: String) -> Bool {
        payload["type"] as? String == "message" && payload["role"] as? String == role
    }

    private static func texts(_ payload: [String: Any]) -> [String] {
        (payload["content"] as? [[String: Any]] ?? [])
            .compactMap { ($0["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func payload(_ line: Data, type: String, marker: String? = nil) -> [String: Any]? {
        guard TranscriptReader.contains(line, #""type":"\#(marker ?? type)""#),
              let obj = TranscriptReader.json(line), obj["type"] as? String == type,
              let payload = obj["payload"] as? [String: Any] else { return nil }
        guard let marker else { return payload }
        return payload["type"] as? String == marker ? payload : nil
    }

    private static func entrypoint(_ sessionMeta: [String: Any]) -> String {
        switch sessionMeta["source"] {
        case let source as String: source
        case nil: sessionMeta["originator"] as? String == "codex_exec" ? "exec" : "cli"
        default: "subagent"
        }
    }

    private static func sessionId(fromFileName url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        return name.count > 36 ? String(name.suffix(36)) : name
    }
}
