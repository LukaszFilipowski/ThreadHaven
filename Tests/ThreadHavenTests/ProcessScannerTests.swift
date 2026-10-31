import Testing
@testable import ThreadHaven

struct ProcessScannerTests {
    @Test func findsNativeAndNodeInstalls() {
        let output = """
        ttys001  S+   claude
        ttys002  S+   /Users/dev/.local/bin/claude --resume abc
        ttys003  R+   node /opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js
        ttys004  Ss+  -zsh
        ttys005  S+   vim claude.md
        ttys006  T    claude
        ttys007  S    claude
        ??       S    /usr/local/bin/claude -p hello
        """
        #expect(ProcessScanner.ttys(fromPSOutput: output) == ["ttys001", "ttys002", "ttys003"])
    }

    @Test func aSuspendedChatWithAnotherForegroundJobDoesNotCount() {
        let suspendedUnderREPL = """
        ttys009  Ss   login -pf someone
        ttys009  S    -zsh
        ttys009  T    claude
        ttys009  T    node /opt/example/mcp-server.js
        ttys009  S+   node
        """
        #expect(ProcessScanner.ttys(fromPSOutput: suspendedUnderREPL).isEmpty)
        let versionNamed = "ttys009  S+   2.1.3 --print\n"
        #expect(ProcessScanner.ttys(fromPSOutput: versionNamed).isEmpty)
    }

    @Test func foregroundCheckRejectsOddTTYNames() {
        #expect(!ProcessScanner.isClaudeInForeground(tty: ""))
        #expect(!ProcessScanner.isClaudeInForeground(tty: "ttys001 -A"))
        #expect(!ProcessScanner.isClaudeInForeground(tty: "../ttys001"))
    }
}
