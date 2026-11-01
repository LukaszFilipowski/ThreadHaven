import Foundation
import ThreadHavenCore

enum ProcessScanner {
    static func agentTTYs() -> [Agent: Set<String>] {
        let output = ps(["-axo", "tty=,stat=,args="])
        return [.claude: ttys(fromPSOutput: output), .codex: ttys(fromPSOutput: output, agent: .codex)]
    }

    static func isInForeground(_ agent: Agent, tty: String) -> Bool {
        guard !tty.isEmpty, tty.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }
        return ttys(fromPSOutput: ps(["-o", "tty=,stat=,args=", "-t", tty]), agent: agent).contains(tty)
    }

    private static func ps(_ arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    static func tty(ofProcess pid: pid_t) -> String? {
        let output = ps(["-o", "tty=", "-p", String(pid)]).trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty || output == "??" ? nil : output
    }

    static func ttys(fromPSOutput output: String, agent: Agent = .claude) -> Set<String> {
        var ttys = Set<String>()
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 3, fields[0] != "??" else { continue }
            let state = fields[1]
            guard state.contains("+"), !state.contains("T") else { continue }
            if runs(agent, fields.dropFirst(2)) { ttys.insert(String(fields[0])) }
        }
        return ttys
    }

    private static func runs(_ agent: Agent, _ args: ArraySlice<Substring>) -> Bool {
        let name = { (arg: Substring) in (String(arg) as NSString).lastPathComponent }
        guard let first = args.first else { return false }
        if name(first) == agent.command { return true }
        guard name(first) == "node", let script = args.dropFirst().first else { return false }
        switch agent {
        case .claude: return script.contains("claude-code") || name(script) == "claude"
        case .codex: return script.contains("@openai/codex/") || ["codex", "codex.js"].contains(name(script))
        }
    }
}
