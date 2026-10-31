import Foundation
import Testing
@testable import ThreadHaven

struct CodexNotifyInstallerTests {
    private let ours = CodexNotifyInstaller.notifyLine(scriptPath: "/Users/dev/.threadhaven/codex-notify.sh")

    @Test func installsAtTopWhenKeyIsAbsent() throws {
        let config = """
        # my settings
        model = "gpt-5"

        [projects."/Users/dev/app"]
        trust_level = "trusted"

        """
        let installed = try CodexNotifyInstaller.installing(into: config, line: ours)
        #expect(installed == ours + "\n" + config)
        #expect(try CodexNotifyInstaller.state(of: installed) == .ours)
        #expect(try CodexNotifyInstaller.removing(from: installed) == config)
    }

    @Test func installsIntoEmptyFile() throws {
        let installed = try CodexNotifyInstaller.installing(into: "", line: ours)
        #expect(installed == ours + "\n")
        #expect(try CodexNotifyInstaller.removing(from: installed) == "")
    }

    @Test func installTwiceKeepsOneLine() throws {
        let once = try CodexNotifyInstaller.installing(into: "model = \"gpt-5\"\n", line: ours)
        #expect(try CodexNotifyInstaller.installing(into: once, line: ours) == once)
    }

    @Test func removesOurLineWherever() throws {
        let config = "model = \"gpt-5\"\n  \(ours)  \n# notify = [\"old\"]\n[tui]\nnotifications = true\n"
        #expect(try CodexNotifyInstaller.state(of: config) == .ours)
        #expect(try CodexNotifyInstaller.removing(from: config) == "model = \"gpt-5\"\n# notify = [\"old\"]\n[tui]\nnotifications = true\n")
    }

    @Test func leavesForeignNotifyAlone() throws {
        for config in [
            "notify = [\"python3\", \"/Users/dev/notify.py\"]\n",
            "notify=[\"/usr/local/bin/ping-me\"]\n",
            "\"notify\" = [\"/usr/local/bin/ping-me\"]\n",
            "notify = [\n  \"/usr/local/bin/ping-me\",\n]\n",
        ] {
            #expect(try CodexNotifyInstaller.state(of: config) == .foreign)
            #expect(throws: CodexNotifyInstaller.Failure.inUse) { try CodexNotifyInstaller.installing(into: config, line: ours) }
            #expect(throws: CodexNotifyInstaller.Failure.inUse) { try CodexNotifyInstaller.removing(from: config) }
        }
    }

    @Test func ignoresNotifyInsideTablesAndComments() throws {
        let config = """
        # notify = ["/usr/local/bin/old"]
        notifyer = 1

        [profiles.work]
        notify = ["/usr/local/bin/work"]
        """
        #expect(try CodexNotifyInstaller.state(of: config) == .absent)
        let installed = try CodexNotifyInstaller.installing(into: config, line: ours)
        #expect(installed.hasPrefix(ours + "\n# notify"))
        #expect(installed.hasSuffix("[profiles.work]\nnotify = [\"/usr/local/bin/work\"]"))
    }

    @Test func refusesUnexpectedContent() {
        for config in ["model = \"gpt-5\"\r\n", "\u{FEFF}model = \"gpt-5\"\n", "instructions = \"\"\"\n[x]\n\"\"\"\n"] {
            #expect(throws: CodexNotifyInstaller.Failure.self) { try CodexNotifyInstaller.installing(into: config, line: ours) }
        }
    }

    @Test func editsThroughSymlinkKeepingBackupAndPermissions() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dotfiles = root.appendingPathComponent("dotfiles")
        let codex = root.appendingPathComponent("codex")
        try fm.createDirectory(at: dotfiles, withIntermediateDirectories: true)
        try fm.createDirectory(at: codex, withIntermediateDirectories: true)
        let real = dotfiles.appendingPathComponent("config.toml")
        let link = codex.appendingPathComponent("config.toml")
        let original = "model = \"gpt-5\"\n\n[tui]\nnotifications = true\n"
        try original.write(to: real, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o640], ofItemAtPath: real.path)
        try fm.createSymbolicLink(at: link, withDestinationURL: real)

        try CodexNotifyInstaller.install(config: link, scriptPath: "/Users/dev/.threadhaven/codex-notify.sh")
        #expect(try fm.destinationOfSymbolicLink(atPath: link.path) == real.path)
        #expect(try String(contentsOf: real, encoding: .utf8) == ours + "\n" + original)
        #expect((try fm.attributesOfItem(atPath: real.path)[.posixPermissions] as? NSNumber)?.intValue == 0o640)
        let backup = dotfiles.appendingPathComponent("config.toml.threadhaven-backup")
        #expect(try String(contentsOf: backup, encoding: .utf8) == original)

        try CodexNotifyInstaller.uninstall(config: link)
        #expect(try String(contentsOf: real, encoding: .utf8) == original)
        #expect(try String(contentsOf: backup, encoding: .utf8) == original)
    }

    @Test func createsMissingConfigPrivately() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let config = root.appendingPathComponent("config.toml")
        try CodexNotifyInstaller.install(config: config, scriptPath: "/Users/dev/.threadhaven/codex-notify.sh")
        #expect(try String(contentsOf: config, encoding: .utf8) == ours + "\n")
        #expect((try FileManager.default.attributesOfItem(atPath: config.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func escapesScriptPath() {
        #expect(CodexNotifyInstaller.notifyLine(scriptPath: "/Users/a\"b/x") == #"notify = ["/Users/a\"b/x"]"#)
    }
}

struct CodexNotifyScriptTests {
    private func run(_ argument: String?, home: URL) throws {
        let script = home.appendingPathComponent("codex-notify.sh")
        try CodexNotifyInstaller.script.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path] + (argument.map { [$0] } ?? [])
        process.environment = ["HOME": home.path, "TERM_PROGRAM": "iTerm.app", "PATH": "/usr/bin:/bin"]
        try process.run()
        process.waitUntilExit()
    }

    private func tempHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func log(in home: URL) -> URL {
        home.appendingPathComponent(".threadhaven/events.jsonl")
    }

    private func decode(_ home: URL) throws -> [HookLine] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try Data(contentsOf: log(in: home)).split(separator: 0x0A).map { try decoder.decode(HookLine.self, from: Data($0)) }
    }

    @Test func writesTurnCompleteWithoutPrompts() throws {
        let home = try tempHome()
        let payload = #"{"type":"agent-turn-complete","thread-id":"0b1c2d3e-0000-4000-8000-00000000abcd","turn-id":"7","cwd":"/Users/dev/my \"app\"","client":"codex-tui","input-messages":["use token abc123","\"cwd\":\"/elsewhere\""],"last-assistant-message":"Done: \"tests\" pass\nNext \\ step"}"#
        try run(payload, home: home)
        #expect(try !String(contentsOf: log(in: home), encoding: .utf8).contains("abc123"))
        let lines = try decode(home)
        #expect(lines.count == 1)
        let line = try #require(lines.first)
        #expect(line.term == "iTerm.app")
        #expect(line.event.sessionId == "0b1c2d3e-0000-4000-8000-00000000abcd")
        #expect(line.event.hookEventName == "CodexTurnComplete")
        #expect(line.event.cwd == "/Users/dev/my \"app\"")
        #expect(line.event.lastAssistantMessage == "Done: \"tests\" pass\nNext \\ step")
        let mode = try FileManager.default.attributesOfItem(atPath: log(in: home).path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
    }

    @Test func handlesMissingAssistantMessage() throws {
        let home = try tempHome()
        try run(#"{"type":"agent-turn-complete","thread-id":"t-1","turn-id":"1","cwd":"/tmp","input-messages":[],"last-assistant-message":null}"#, home: home)
        let line = try #require(try decode(home).first)
        #expect(line.event.sessionId == "t-1")
        #expect(line.event.lastAssistantMessage == "")
    }

    @Test func ignoresOtherInput() throws {
        let home = try tempHome()
        try run(nil, home: home)
        try run(#"{"type":"something-else","thread-id":"t-2"}"#, home: home)
        try run(#"{"type":"agent-turn-complete","thread-id":"","cwd":"/tmp"}"#, home: home)
        #expect(!FileManager.default.fileExists(atPath: log(in: home).path))
    }

    @Test func sanitizesThreadId() throws {
        let home = try tempHome()
        try run(#"{"type":"agent-turn-complete","thread-id":"a\"},\"x\":{\"b","cwd":"/tmp"}"#, home: home)
        let line = try #require(try decode(home).first)
        #expect(line.event.sessionId == "axb")
    }
}
