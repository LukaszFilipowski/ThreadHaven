import Testing
@testable import ThreadHaven

struct TerminalSendTests {
    @Test func terminalScriptChecksTheForegroundProcessBeforeTyping() throws {
        let script = try #require(TerminalBridge.sendScript("Run the \"tests\"", app: .terminal, tty: "ttys005"))
        let check = try #require(script.range(of: "set n to last item of p"))
        let type = try #require(script.range(of: #"do script "Run the \"tests\"" in t"#))
        #expect(check.upperBound < type.lowerBound)
        #expect(script.contains(#"if n is not in {"claude", "codex", "node"} and (character 1 of n is not in "0123456789" or n does not contain ".") then return false"#))
        #expect(script.contains(#"if tty of t is "/dev/ttys005""#))
    }

    @Test func itermScriptChecksTheJobNameBeforeTyping() throws {
        let script = try #require(TerminalBridge.sendScript("hello", app: .iterm, tty: "ttys002"))
        let check = try #require(script.range(of: #"variable named "jobName""#))
        let type = try #require(script.range(of: #"write text "hello""#))
        #expect(check.upperBound < type.lowerBound)
        #expect(script.contains("then return false"))
    }

    @Test func refusesUnsupportedTerminalsAndOddTTYs() {
        #expect(TerminalBridge.sendScript("x", app: .ghostty, tty: "ttys001") == nil)
        #expect(TerminalBridge.sendScript("x", app: .terminal, tty: "ttys001\" or true") == nil)
    }

    @Test func closeTabOnlyTouchesTheMatchingIdleTab() throws {
        let script = try #require(TerminalBridge.closeTabScript(tty: "ttys007", bundle: TerminalApp.terminal.rawValue))
        #expect(script.contains("\"/dev/ttys007\""))
        #expect(script.contains("if busy of t then return false"))
        #expect(script.contains("if (count of tabs of w) is not 1 then return false"))
        #expect(TerminalBridge.closeTabScript(tty: "ttys0; rm", bundle: TerminalApp.terminal.rawValue) == nil)
        #expect(TerminalBridge.closeTabScript(tty: "ttys001", bundle: TerminalApp.ghostty.rawValue) == nil)
    }

    @MainActor @Test func embeddedTerminalDropsTheParentClaudeSession() {
        let env = EmbeddedTerminals.environment(for: .codex, base: ["CLAUDE_CODE_CHILD_SESSION": "1", "CLAUDECODE": "1", "HOME": "/Users/x"])
        #expect(!env.contains { $0.hasPrefix("CLAUDE_CODE_CHILD_SESSION=") || $0.hasPrefix("CLAUDECODE=") })
        #expect(env.contains("HOME=/Users/x"))
    }
}
