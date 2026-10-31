import Foundation

enum ProcessScanner {
    static func claudeTTYs() -> Set<String> {
        ttys(fromPSOutput: ps(["-axo", "tty=,stat=,args="]))
    }

    static func isClaudeInForeground(tty: String) -> Bool {
        guard !tty.isEmpty, tty.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }
        return ttys(fromPSOutput: ps(["-o", "tty=,stat=,args=", "-t", tty])).contains(tty)
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

    static func ttys(fromPSOutput output: String) -> Set<String> {
        var ttys = Set<String>()
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 3, fields[0] != "??" else { continue }
            let state = fields[1]
            guard state.contains("+"), !state.contains("T") else { continue }
            if isClaude(fields.dropFirst(2)) { ttys.insert(String(fields[0])) }
        }
        return ttys
    }

    private static func isClaude(_ args: ArraySlice<Substring>) -> Bool {
        let name = { (arg: Substring) in (String(arg) as NSString).lastPathComponent }
        guard let first = args.first else { return false }
        if name(first) == "claude" { return true }
        guard name(first) == "node", let script = args.dropFirst().first else { return false }
        return script.contains("claude-code") || name(script) == "claude"
    }
}
