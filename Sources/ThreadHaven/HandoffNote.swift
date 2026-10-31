import Foundation
import ThreadHavenCore

extension Handoff {
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
        let folder = folder(for: cwd, home: home)
        try HookInstaller.secureDirectory(folder.deletingLastPathComponent().deletingLastPathComponent())
        try HookInstaller.secureDirectory(folder.deletingLastPathComponent())
        try HookInstaller.secureDirectory(folder)
        let file = folder.appendingPathComponent("\(fileDateFormatter().string(from: date))-\(sessionId.prefix(8)).md")
        try Data(note.utf8).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return file
    }

    static func folder(for cwd: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        let project = (cwd as NSString).lastPathComponent
        return home.appendingPathComponent(".threadhaven/handoffs", isDirectory: true)
            .appendingPathComponent(project.isEmpty ? "unknown" : project, isDirectory: true)
    }

    static func fileDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }
}
