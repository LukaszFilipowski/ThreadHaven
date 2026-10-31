import Foundation
import ThreadHavenCore

nonisolated enum TerminalLauncher {
    static let terminals: [[String]] = [
        ["xdg-terminal-exec"],
        ["kgx", "--"],
        ["gnome-terminal", "--"],
        ["konsole", "-e"],
        ["x-terminal-emulator", "-e"],
    ]

    static var isSandboxed: Bool {
        FileManager.default.fileExists(atPath: "/.flatpak-info")
    }

    static func resume(_ meta: TranscriptMeta) -> Bool {
        let command = [meta.agent.command] + meta.agent.resumeArguments(meta.sessionId)
        guard let terminal = terminals.first(where: { isAvailable($0[0]) }) else { return false }
        return launch(terminal + command, in: meta.cwd)
    }

    private static func isAvailable(_ name: String) -> Bool {
        guard isSandboxed else { return executable(named: name) != nil }
        let process = Process()
        guard let spawn = executable(named: "flatpak-spawn") else { return false }
        process.executableURL = spawn
        process.arguments = ["--host", "which", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func launch(_ arguments: [String], in directory: String?) -> Bool {
        let process = Process()
        if isSandboxed {
            guard let spawn = executable(named: "flatpak-spawn") else { return false }
            process.executableURL = spawn
            process.arguments = ["--host"] + (directory.map { ["--directory=\($0)"] } ?? []) + arguments
        } else {
            guard let terminal = executable(named: arguments[0]) else { return false }
            process.executableURL = terminal
            process.arguments = Array(arguments.dropFirst())
            if let directory, FileManager.default.fileExists(atPath: directory) {
                process.currentDirectoryURL = URL(fileURLWithPath: directory)
            }
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    private static func executable(named name: String) -> URL? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin"
        return path.split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
