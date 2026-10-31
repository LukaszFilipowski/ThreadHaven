import Testing
@testable import ThreadHaven

struct ProcessScannerTests {
    @Test func findsNativeAndNodeInstalls() {
        let output = """
        ttys001  claude
        ttys002  /Users/dev/.local/bin/claude --resume abc
        ttys003  node /opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js
        ttys004  -zsh
        ttys005  vim claude.md
        ??       /usr/local/bin/claude -p hello
        """
        #expect(ProcessScanner.ttys(fromPSOutput: output) == ["ttys001", "ttys002", "ttys003"])
    }
}
