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
            try execute(["-p", "--model", model] + isolationArguments + [instruction], input: input)
        }.value
    }

    static func command(_ arguments: [String], in directory: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try execute(arguments, input: "", directory: directory)
        }.value
    }

    private static func execute(
        _ arguments: [String],
        input: String,
        directory: URL = FileManager.default.temporaryDirectory
    ) throws -> String {
        guard let claude = resolvePath() else { throw Failure.notFound }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claude)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let stdin = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = stdin
        process.standardOutput = output
        process.standardError = errors
        try process.run()

        let group = DispatchGroup()
        var errorData = Data()
        DispatchQueue.global().async(group: group) {
            stdin.fileHandleForWriting.write(Data(input.utf8))
            try? stdin.fileHandleForWriting.close()
        }
        DispatchQueue.global().async(group: group) {
            errorData = errors.fileHandleForReading.readDataToEndOfFile()
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw Failure.failed(String(decoding: errorData.isEmpty ? data : errorData, as: UTF8.self))
        }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
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
