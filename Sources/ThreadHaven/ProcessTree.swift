import Darwin
import Foundation
import ThreadHavenCore

enum ProcessTree {
    static func descendants(of root: pid_t) -> [pid_t] {
        let output = run(["-axo", "pid=,ppid="])
        var children: [pid_t: [pid_t]] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count == 2, let pid = pid_t(fields[0]), let parent = pid_t(fields[1]) else { continue }
            children[parent, default: []].append(pid)
        }
        var result: [pid_t] = []
        var queue = children[root] ?? []
        while let pid = queue.popLast() {
            result.append(pid)
            queue += children[pid] ?? []
        }
        return result
    }

    static func terminate(_ root: pid_t) {
        guard root > 1 else { return }
        let tree = [root] + descendants(of: root)
        tree.forEach { kill($0, SIGTERM) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            tree.filter { kill($0, 0) == 0 }.forEach { kill($0, SIGKILL) }
        }
    }

    static func agentProcess(on tty: String, agent: Agent) -> pid_t? {
        guard !tty.isEmpty, tty.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        for line in run(["-o", "pid=,tty=,stat=,args=", "-t", tty]).split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4, let pid = pid_t(fields[0]) else { continue }
            if ProcessScanner.ttys(fromPSOutput: "\(fields[1]) S+ \(fields[3])", agent: agent).contains(String(fields[1])) {
                return pid
            }
        }
        return nil
    }

    private static func run(_ arguments: [String]) -> String {
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
}
