import Foundation

public enum Handoff {
    public static let cutMarker = "[… earlier conversation omitted …]"
    static let tailBytes: UInt64 = 8_000_000
    static let entryLimit = 4_000
    static let toolInputLimit = 200
    static let toolInputKeys = ["file_path", "command", "pattern", "path", "url", "query", "description"]

    public static func digest(path: String, budget: Int = 60_000) -> String {
        let url = URL(fileURLWithPath: path)
        let chunk = TranscriptReader.readChunk(url: url, fromEnd: true, bytes: tailBytes)
        let entries = TranscriptReader.lines(chunk).flatMap(digestLines)
        var kept: [String] = []
        var used = 0
        for entry in entries.reversed() {
            used += entry.count + 1
            guard used <= budget else { break }
            kept.append(entry)
        }
        let body = kept.reversed().joined(separator: "\n")
        let isCut = kept.count < entries.count || (TranscriptReader.stamp(of: url)?.size ?? 0) > tailBytes
        return isCut ? cutMarker + "\n" + body : body
    }

    private static func digestLines(_ line: Data) -> [String] {
        guard let obj = TranscriptReader.json(line),
              obj["isSidechain"] as? Bool != true, obj["isMeta"] as? Bool != true else { return [] }
        switch obj["type"] as? String {
        case "user":
            guard let text = TranscriptReader.userText(obj), !text.isEmpty, !text.hasPrefix("<") else { return [] }
            return ["User: " + clip(text, entryLimit)]
        case "assistant":
            let blocks = (obj["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            return blocks.compactMap(digestLine)
        default:
            return []
        }
    }

    private static func digestLine(_ block: [String: Any]) -> String? {
        switch block["type"] as? String {
        case "text":
            guard let text = (block["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            return "Assistant: " + clip(text, entryLimit)
        case "tool_use":
            let name = block["name"] as? String ?? "tool"
            let input = block["input"] as? [String: Any] ?? [:]
            guard let detail = toolInputKeys.lazy.compactMap({ input[$0] as? String }).first else { return "Tool: \(name)" }
            return "Tool: \(name) " + clip(detail.replacingOccurrences(of: "\n", with: " "), toolInputLimit)
        default:
            return nil
        }
    }

    private static func clip(_ text: String, _ limit: Int) -> String {
        text.count > limit ? text.prefix(limit) + "…" : text
    }
}
