import AppKit
import ThreadHavenCore

enum TerminalApp: String, CaseIterable, Identifiable {
    case terminal = "com.apple.Terminal"
    case iterm = "com.googlecode.iterm2"
    case ghostty = "com.mitchellh.ghostty"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .terminal: "Terminal"
        case .iterm: "iTerm2"
        case .ghostty: "Ghostty"
        }
    }

    var canSendText: Bool { self != .ghostty }
}

enum TerminalBridge {
    static let termPrograms = [
        "Apple_Terminal": TerminalApp.terminal.rawValue,
        "iTerm.app": TerminalApp.iterm.rawValue,
        "ghostty": TerminalApp.ghostty.rawValue,
        "vscode": "com.microsoft.VSCode",
        "WarpTerminal": "dev.warp.Warp-Stable",
        "WezTerm": "com.github.wez.wezterm",
    ]

    static let knownBundles = Set(termPrograms.values)

    static func bundle(forTermProgram term: String?) -> String? {
        term.flatMap { termPrograms[$0] }
    }

    static func canSend(to session: Session) -> Bool {
        guard session.agent == .claude, session.isLive, let b = session.terminalBundle, let app = TerminalApp(rawValue: b) else { return false }
        return app.canSendText
    }

    @discardableResult
    static func focus(_ session: Session) -> Bool {
        guard let bundle = session.terminalBundle else { return false }
        if let tty = session.live?.tty, session.isLive {
            let dev = "/dev/" + tty
            switch TerminalApp(rawValue: bundle) {
            case .terminal:
                return run("""
                tell application id "\(bundle)"
                    repeat with w in windows
                        repeat with t in tabs of w
                            if tty of t is "\(dev)" then
                                set selected of t to true
                                set index of w to 1
                                activate
                                return true
                            end if
                        end repeat
                    end repeat
                    activate
                end tell
                """)
            case .iterm:
                return run("""
                tell application id "\(bundle)"
                    repeat with w in windows
                        repeat with t in tabs of w
                            repeat with s in sessions of t
                                if tty of s is "\(dev)" then
                                    select w
                                    select t
                                    select s
                                    activate
                                    return true
                                end if
                            end repeat
                        end repeat
                    end repeat
                    activate
                end tell
                """)
            default:
                break
            }
        }
        return activate(bundle)
    }

    @discardableResult
    static func send(_ text: String, to session: Session) -> Bool {
        guard canSend(to: session), let bundle = session.terminalBundle, let tty = session.live?.tty else { return false }
        let flat = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let body = escape(flat)
        let dev = "/dev/" + tty
        switch TerminalApp(rawValue: bundle) {
        case .terminal:
            return run("""
            tell application id "\(bundle)"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(dev)" then
                            do script "\(body)" in t
                            return true
                        end if
                    end repeat
                end repeat
            end tell
            return false
            """)
        case .iterm:
            return run("""
            tell application id "\(bundle)"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(dev)" then
                                tell s to write text "\(body)"
                                return true
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return false
            """)
        default:
            return false
        }
    }

    static func openNew(cwd: String, agent: Agent = .claude, arguments: [String], terminal: TerminalApp) {
        let launch = invocation(agent, arguments)
        let command = ["cd", shellQuote(cwd), "&&", launch].joined(separator: " ")
        switch terminal {
        case .terminal:
            run("""
            tell application id "\(terminal.rawValue)"
                activate
                do script "\(escape(command))"
            end tell
            """)
        case .iterm:
            run("""
            tell application id "\(terminal.rawValue)"
                activate
                set w to (create window with default profile)
                tell current session of w to write text "\(escape(command))"
            end tell
            """)
        case .ghostty:
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-na", "Ghostty", "--args", "--working-directory=\(cwd)", "-e", "/bin/zsh", "-lic", launch]
            try? p.run()
        }
    }

    @discardableResult
    private static func activate(_ bundle: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return false }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        return true
    }

    @discardableResult
    private static func run(_ source: String) -> Bool {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { NSLog("ThreadHaven AppleScript error: \(error)") }
        return error == nil && (result?.booleanValue ?? true)
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func invocation(_ agent: Agent, _ arguments: [String]) -> String {
        ([agent.command] + arguments.map(shellQuote)).joined(separator: " ")
    }

    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
