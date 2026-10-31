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
        #expect(ProcessScanner.ttys(fromPSOutput: output, agent: .codex).isEmpty)
    }

    @Test func findsCodexInstalls() {
        let output = """
        ttys001  S+   codex
        ttys002  S+   /opt/homebrew/bin/codex resume abc
        ttys003  S+   node /Users/dev/.npm-global/bin/codex
        ttys004  S+   /usr/local/bin/node /usr/local/lib/node_modules/@openai/codex/bin/codex.js
        ttys004  S+   /usr/local/lib/node_modules/@openai/codex/vendor/aarch64-apple-darwin/bin/codex
        ttys005  S+   claude
        ttys006  T+   codex
        ttys007  S    codex
        ttys008  S+   vim codex.md
        ??       S    /opt/homebrew/bin/codex exec hello
        """
        #expect(ProcessScanner.ttys(fromPSOutput: output, agent: .codex) == ["ttys001", "ttys002", "ttys003", "ttys004"])
        #expect(ProcessScanner.ttys(fromPSOutput: output) == ["ttys005"])
    }
}
