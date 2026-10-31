import Foundation

enum ClaudeCLI {
    enum Failure: LocalizedError {
        case notFound
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notFound: String(localized: "The claude command was not found in your login shell PATH.")
            case .failed(let msg): msg
            }
        }
    }

    static let isolationArguments = [
        "--tools", "",
        "--strict-mcp-config",
        "--disable-slash-commands",
        "--no-session-persistence",
    ]

    static func run(_ instruction: String, input: String, model: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            guard let claude = resolvePath() else { throw Failure.notFound }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: claude)
            p.arguments = ["-p", "--model", model] + isolationArguments + [instruction]
            p.currentDirectoryURL = FileManager.default.temporaryDirectory
            let stdin = Pipe()
            let output = Pipe()
            let errors = Pipe()
            p.standardInput = stdin
            p.standardOutput = output
            p.standardError = errors
            try p.run()
            stdin.fileHandleForWriting.write(Data(input.utf8))
            try stdin.fileHandleForWriting.close()
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

    static func resolvePath() -> String? {
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
