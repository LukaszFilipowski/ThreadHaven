import Foundation
import ThreadHavenCore

struct Options {
    var days = 14
    var thresholds = [100_000, 150_000, 200_000]
    var summaryTokens = CompactionSimulation.defaultSummaryTokens
    var projects = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")

    init(_ arguments: [String]) {
        var iterator = arguments.makeIterator()
        while let flag = iterator.next() {
            let value = iterator.next() ?? ""
            switch flag {
            case "--days": days = Int(value) ?? days
            case "--thresholds": thresholds = value.split(separator: ",").compactMap { Int($0) }
            case "--summary": summaryTokens = Int(value) ?? summaryTokens
            case "--projects": projects = URL(fileURLWithPath: value)
            default:
                print("usage: threadhaven-stats [--days 14] [--thresholds 100000,150000,200000] [--summary 20000] [--projects ~/.claude/projects]")
                exit(flag == "--help" ? 0 : 1)
            }
        }
    }
}

func transcripts(in root: URL, since: Date) -> [URL] {
    let fm = FileManager.default
    let keys: [URLResourceKey] = [.contentModificationDateKey]
    let folders = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
    return folders.flatMap { folder in
        ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []).filter {
            $0.pathExtension == "jsonl"
                && ((try? $0.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? .distantPast) >= since
        }
    }
}

func isInteractive(_ url: URL) -> Bool {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
    defer { try? handle.close() }
    let head = String(decoding: (try? handle.read(upToCount: 256_000)) ?? Data(), as: UTF8.self)
    return head.contains(#""entrypoint":"cli""#)
}

func short(_ n: Int) -> String {
    switch n {
    case 1_000_000_000...: String(format: "%.1fB", Double(n) / 1e9)
    case 1_000_000...: String(format: "%.1fM", Double(n) / 1e6)
    case 1_000...: "\(n / 1_000)k"
    default: "\(n)"
    }
}

func percent(_ share: Double) -> String { String(format: "%.0f%%", share * 100) }

let options = Options(Array(CommandLine.arguments.dropFirst()))
let since = Date().addingTimeInterval(-Double(options.days) * 86_400)
let files = transcripts(in: options.projects, since: since).filter(isInteractive)

let lock = NSLock()
var sessions: [TokenStats] = []
DispatchQueue.concurrentPerform(iterations: files.count) { index in
    let stats = TokenStats.analyze(url: files[index])
    guard stats.turns > 0 else { return }
    lock.withLock { sessions.append(stats) }
}

let replies = sessions.reduce(0) { $0 + $1.turns }
let processed = sessions.reduce(0) { $0 + $1.contexts.reduce(0, +) }
let baselines = sessions.map(\.baselineContext).sorted()
let medianBaseline = baselines.isEmpty ? 0 : baselines[baselines.count / 2]
let coldRebuilds = sessions.reduce(0) { $0 + $1.coldRebuilds }
let coldRebuildTokens = sessions.reduce(0) { $0 + $1.coldRebuildTokens }
let cacheWrites = sessions.reduce(0) { $0 + $1.cacheWriteTokens }

print("""
# ThreadHaven token report

Interactive Claude Code sessions from the last \(options.days) days: \(sessions.count) sessions, \(replies) replies.

| Metric | Value |
| --- | --- |
| Context processed (sum of context size over all replies) | \(short(processed)) |
| Average context per reply | \(short(replies > 0 ? processed / replies : 0)) |
| Context at the first reply (median) | \(short(medianBaseline)) |
| Cold cache rebuilds | \(coldRebuilds) (\(short(coldRebuildTokens)) tokens, \(percent(cacheWrites > 0 ? Double(coldRebuildTokens) / Double(cacheWrites) : 0)) of all cache writes) |

## Compacting at a fixed size (simulation)

Each reply re-reads the whole context. This replays every session and compacts it whenever the context grows past the threshold, restarting from the first-reply context plus a \(short(options.summaryTokens)) summary. The context read by the compaction itself is counted.

| Threshold | Compactions | Context processed | Saved | Work for the same context |
| --- | --- | --- | --- | --- |
""")

for threshold in options.thresholds {
    var simulation = CompactionSimulation(threshold: threshold)
    for stats in sessions {
        simulation.add(contexts: stats.contexts, baseline: stats.baselineContext, summaryTokens: options.summaryTokens)
    }
    let factor = simulation.simulatedTokens > 0 ? Double(simulation.actualTokens) / Double(simulation.simulatedTokens) : 1
    print("| \(short(threshold)) | \(simulation.compactions) | \(short(simulation.simulatedTokens)) | \(percent(simulation.savedShare)) | \(String(format: "%.1f×", factor)) |")
}
