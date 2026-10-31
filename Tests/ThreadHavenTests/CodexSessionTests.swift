import Foundation
import Testing
@testable import ThreadHaven
import ThreadHavenCore

struct CodexSessionTests {
    private func meta(entrypoint: String) -> TranscriptMeta {
        TranscriptMeta(
            agent: .codex,
            sessionId: "0199aaaa-bbbb-7ccc-8ddd-eeeeeeeeeeee",
            path: "/tmp/rollout.jsonl",
            cwd: "/Users/dev/project",
            firstPrompt: "Add a dark mode toggle to the settings screen",
            entrypoint: entrypoint,
            modified: .distantPast,
            size: 0
        )
    }

    @Test func titleAndProjectComeFromMeta() {
        let session = Session(id: "codex", meta: meta(entrypoint: "cli"))
        #expect(session.title == "Add a dark mode toggle to the settings screen")
        #expect(session.project == "project")
    }

    @Test func execRunsAreBackgroundSessions() {
        let interactive = Session(id: "interactive", meta: meta(entrypoint: "cli"))
        let exec = Session(id: "exec", meta: meta(entrypoint: "exec"))
        #expect(interactive.isInteractive)
        #expect(!exec.isInteractive)
        #expect(interactive.status == .closed)
        #expect(!TerminalBridge.canSend(to: interactive))
    }

    @Test func resumeCommandIsQuoted() {
        #expect(TerminalBridge.invocation(.codex, Agent.codex.resumeArguments("a'b")) == #"codex 'resume' 'a'\''b'"#)
        #expect(TerminalBridge.invocation(.claude, Agent.claude.resumeArguments("id")) == "claude '--resume' 'id'")
    }
}
