import AppKit
import Observation
import SwiftTerm
import ThreadHavenCore

@MainActor
@Observable
final class EmbeddedTerminals {
    struct Pending: Identifiable, Equatable {
        let id: String
        let cwd: String
        let agent: Agent
        var linkedSession: String?
        var project: String { (cwd as NSString).lastPathComponent }
    }

    private(set) var running: Set<String> = []
    private(set) var pending: [Pending] = []

    private var views: [String: LocalProcessTerminalView] = [:]
    @ObservationIgnored private var observers: [String: ProcessObserver] = [:]

    func view(for id: String) -> LocalProcessTerminalView? { views[id] }

    func isRunning(_ id: String) -> Bool { running.contains(id) }

    @discardableResult
    func open(id: String, cwd: String, agent: Agent, arguments: [String]) -> Bool {
        if running.contains(id) { return true }
        guard let executable = Self.executable(for: agent) else { return false }
        let view = views[id] ?? Self.makeView()
        let observer = ProcessObserver { [weak self] in
            MainActor.assumeIsolated { self?.ended(id) }
        }
        view.processDelegate = observer
        observers[id] = observer
        views[id] = view
        view.startProcess(
            executable: "/bin/zsh",
            args: ["-l", "-c", "exec \"$0\" \"$@\"", executable] + arguments,
            environment: Self.environment(),
            execName: nil,
            currentDirectory: cwd
        )
        running.insert(id)
        return true
    }

    func startNew(cwd: String, agent: Agent, arguments: [String]) -> String? {
        let id = "new-" + UUID().uuidString
        guard open(id: id, cwd: cwd, agent: agent, arguments: arguments) else { return nil }
        pending.append(Pending(id: id, cwd: cwd, agent: agent))
        return id
    }

    @ObservationIgnored private var ttyCache: [String: String] = [:]

    func tty(for id: String) -> String? {
        if let tty = ttyCache[id] { return tty }
        guard let pid = processID(for: id), let tty = ProcessScanner.tty(ofProcess: pid) else { return nil }
        ttyCache[id] = tty
        return tty
    }

    func processID(for id: String) -> pid_t? {
        guard running.contains(id), let pid = views[id]?.process.shellPid, pid > 0 else { return nil }
        return pid
    }

    var hasUnlinkedPending: Bool { pending.contains { $0.linkedSession == nil } }

    func link(pending id: String, to sessionId: String) {
        guard let index = pending.firstIndex(where: { $0.id == id }), pending[index].linkedSession != sessionId else { return }
        pending[index].linkedSession = sessionId
    }

    var ids: [String] { Array(views.keys) }

    func adopt(pending id: String, as sessionId: String) {
        guard id != sessionId, let view = views.removeValue(forKey: id) else { return }
        views[sessionId] = view
        observers[sessionId] = observers.removeValue(forKey: id)
        if running.remove(id) != nil { running.insert(sessionId) }
        ttyCache[sessionId] = ttyCache.removeValue(forKey: id)
        pending.removeAll { $0.id == id }
        let observer = ProcessObserver { [weak self] in
            MainActor.assumeIsolated { self?.ended(sessionId) }
        }
        view.processDelegate = observer
        observers[sessionId] = observer
    }

    @discardableResult
    func send(_ text: String, to id: String) -> Bool {
        guard running.contains(id), let view = views[id] else { return false }
        view.send(txt: text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            view.send([13])
        }
        return true
    }

    func close(_ id: String) {
        if let pid = processID(for: id) { ProcessTree.terminate(pid) }
        ended(id)
    }

    private func ended(_ id: String) {
        running.remove(id)
        ttyCache[id] = nil
        pending.removeAll { $0.id == id }
    }

    private static func makeView() -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        view.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        view.nativeBackgroundColor = .textBackgroundColor
        view.nativeForegroundColor = .textColor
        view.caretColor = .controlAccentColor
        view.optionAsMetaKey = true
        return view
    }

    private static func executable(for agent: Agent) -> String? {
        switch agent {
        case .claude: ClaudeCLI.resolvePath()
        case .codex: CodexCLI.resolvePath()
        }
    }

    private static func environment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "ThreadHaven"
        env["__CFBundleIdentifier"] = Bundle.main.bundleIdentifier ?? "app.threadhaven.ThreadHaven"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        return env.map { "\($0.key)=\($0.value)" }
    }
}

private final class ProcessObserver: LocalProcessTerminalViewDelegate {
    let onExit: () -> Void

    init(onExit: @escaping () -> Void) {
        self.onExit = onExit
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { self.onExit() }
    }
}

enum CodexCLI {
    nonisolated(unsafe) private static var cachedPath: String?

    static func resolvePath() -> String? {
        if let cachedPath { return cachedPath }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(home)/.local/bin/codex"]
        if let hit = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            cachedPath = hit
            return hit
        }
        let process = Process()
        let out = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v codex"]
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else { return nil }
        cachedPath = path
        return path
    }
}
