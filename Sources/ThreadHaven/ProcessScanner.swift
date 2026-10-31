import Foundation

enum ProcessScanner {
    static func claudeTTYs() -> Set<String> {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "tty=,args="]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ttys(fromPSOutput: String(decoding: data, as: UTF8.self))
    }

    static func ttys(fromPSOutput output: String) -> Set<String> {
        var ttys = Set<String>()
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 2, fields[0] != "??" else { continue }
            if isClaude(fields.dropFirst()) { ttys.insert(String(fields[0])) }
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
