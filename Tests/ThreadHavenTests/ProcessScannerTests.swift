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
}
