import Foundation

enum PromptPolisher {
    enum Failure: LocalizedError {
        case claudeNotFound
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .claudeNotFound: String(localized: "The claude command was not found in your login shell PATH.")
            case .failed(let msg): msg
            }
        }
    }

    static let instruction = """
    Rewrite the dictated note below into a clear, well-structured prompt for Claude Code (a coding agent). \
    Keep the original language of the note. Fix punctuation, typos and speech-recognition mistakes. \
    If the note contains several tasks, list them as bullet points. Do not add requirements that are not in the note. \
    Output only the final prompt text, with no preamble.
    """

    static func polish(_ text: String, model: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            guard let claude = resolveClaude() else { throw Failure.claudeNotFound }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: claude)
            p.arguments = ["-p", "--model", model, "--strict-mcp-config", instruction]
            p.currentDirectoryURL = FileManager.default.temporaryDirectory
            let input = Pipe()
            let output = Pipe()
            let errors = Pipe()
            p.standardInput = input
            p.standardOutput = output
            p.standardError = errors
            try p.run()
            input.fileHandleForWriting.write(Data(text.utf8))
            try input.fileHandleForWriting.close()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let err = errors.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                throw Failure.failed(String(decoding: err.isEmpty ? data : err, as: UTF8.self))
            }
            return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }

    nonisolated(unsafe) private static var cachedPath: String?

    static func resolveClaude() -> String? {
        if let cachedPath { return cachedPath }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(home)/.claude/local/claude"]
        if let hit = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            cachedPath = hit
            return hit
        }
        let p = Process()
        let out = Pipe()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "command -v claude"]
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else { return nil }
        cachedPath = path
        return path
    }
}
