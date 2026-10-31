import Foundation

enum ProcessScanner {
    static func claudeTTYs() -> Set<String> {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "tty=,comm="]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        var ttys = Set<String>()
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, parts[0] != "??" else { continue }
            let command = String(parts[1]).trimmingCharacters(in: .whitespaces)
            if (command as NSString).lastPathComponent == "claude" {
                ttys.insert(String(parts[0]))
            }
        }
        return ttys
    }
}
