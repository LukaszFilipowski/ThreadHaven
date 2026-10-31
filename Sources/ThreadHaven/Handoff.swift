import Foundation

enum Handoff {
    enum Failure: LocalizedError {
        case nothingToHandOff

        var errorDescription: String? {
            switch self {
            case .nothingToHandOff: String(localized: "This chat has no messages to hand off.")
            }
        }
    }

    static let instruction = """
    The input is a condensed transcript of a long Claude Code session, oldest first. \
    Write a handoff note so a fresh Claude Code session can continue the work without the old history. \
    Write it in the language the user used in the conversation, as concise markdown with these sections: \
    goal, current state, key decisions, files touched, open TODOs and the exact next step. \
    Be specific: name files, commands and values. Do not invent anything that is not in the transcript. \
    Output only the note, with no preamble.
    """

    static let cutMarker = "[… earlier conversation omitted …]"
    static let tailBytes: UInt64 = 8_000_000
    static let entryLimit = 4_000
    static let toolInputLimit = 200
    static let toolInputKeys = ["file_path", "command", "pattern", "path", "url", "query", "description"]

    static func digest(path: String, budget: Int = 60_000) -> String {
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

    static func summarize(digest: String, cwd: String, model: String) async throws -> String {
        guard !digest.isEmpty else { throw Failure.nothingToHandOff }
        return try await ClaudeCLI.run(instruction, input: "Project folder: \(cwd)\n\n\(digest)", model: model)
    }

    static func save(
        note: String,
        sessionId: String,
        cwd: String,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        date: Date = .now
    ) throws -> URL {
        let project = (cwd as NSString).lastPathComponent
        let folder = home.appendingPathComponent(".threadhaven/handoffs", isDirectory: true)
            .appendingPathComponent(project.isEmpty ? "unknown" : project, isDirectory: true)
        try HookInstaller.secureDirectory(folder.deletingLastPathComponent().deletingLastPathComponent())
        try HookInstaller.secureDirectory(folder.deletingLastPathComponent())
        try HookInstaller.secureDirectory(folder)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let file = folder.appendingPathComponent("\(formatter.string(from: date))-\(sessionId.prefix(8)).md")
        try Data(note.utf8).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return file
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
