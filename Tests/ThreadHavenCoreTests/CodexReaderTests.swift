import Foundation
import Testing
@testable import ThreadHavenCore

struct CodexReaderTests {
    let root = Bundle.module.url(forResource: "codex", withExtension: nil, subdirectory: "Fixtures")!
    let interactiveId = "0199aaaa-bbbb-7ccc-8ddd-eeeeeeeeeeee"
    let execId = "0199ffff-eeee-7ddd-8ccc-bbbbbbbbbbbb"

    private func metas() -> [String: TranscriptMeta] {
        let files = CodexReader.listSessions(since: .distantPast, in: root)
        let metas = files.map { CodexReader.readMeta(url: $0.key, stamp: $0.value) }
        return Dictionary(uniqueKeysWithValues: metas.map { ($0.sessionId, $0) })
    }

    @Test func listsRolloutsWithinWindow() {
        #expect(CodexReader.listSessions(since: .distantPast, in: root).count == 2)
        #expect(CodexReader.listSessions(since: .distantFuture, in: root).isEmpty)
        #expect(CodexReader.listSessions(since: .distantPast, in: root.appendingPathComponent("missing")).isEmpty)
    }

    @Test func readsSessionMetadata() throws {
        let meta = try #require(metas()[interactiveId])
        #expect(meta.agent == .codex)
        #expect(meta.cwd == "/Users/dev/project")
        #expect(meta.entrypoint == "cli")
        #expect(meta.model == "gpt-5.1-codex")
        #expect(meta.contextTokens == 24_000)
        #expect(meta.contextWindow == 272_000)
        #expect(meta.lastReplyAt == nil)
        #expect(meta.baselineContext == nil)
    }

    @Test func injectedContextIsNotAPrompt() throws {
        let meta = try #require(metas()[interactiveId])
        #expect(meta.firstPrompt == "Add a dark mode toggle to the settings screen")
        #expect(meta.lastPrompt == "Now add a test for it")
    }

    @Test func execRunsHaveExecEntrypoint() throws {
        #expect(try #require(metas()[execId]).entrypoint == "exec")
    }

    @Test func recentMessagesKeepPromptsAndReplies() throws {
        let path = try #require(metas()[interactiveId]).path
        let messages = CodexReader.recentMessages(path: path)
        #expect(messages.map(\.text) == [
            "Add a dark mode toggle\nto the settings screen",
            "I will add the **toggle**.",
            "Now add a test for it",
            "Added the test.",
        ])
        #expect(messages.map(\.role) == [.user, .assistant, .user, .assistant])
        #expect(messages.first?.date == TranscriptReader.parseDate("2026-10-31T10:00:01.200Z"))
    }
}
