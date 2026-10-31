import Foundation
import Testing
@testable import ThreadHaven

struct TranscriptReaderTests {
    let url = Bundle.module.url(forResource: "session", withExtension: "jsonl", subdirectory: "Fixtures")!

    private func meta() throws -> TranscriptMeta {
        let stamp = try #require(TranscriptReader.stamp(of: url))
        return TranscriptReader.readMeta(url: url, stamp: stamp)
    }

    @Test func readsSessionMetadata() throws {
        let meta = try meta()
        #expect(meta.sessionId == "session")
        #expect(meta.title == "Login screen")
        #expect(meta.cwd == "/Users/dev/projects/demo")
        #expect(meta.entrypoint == "cli")
        #expect(meta.firstPrompt == "Add a login screen with email and password")
        #expect(meta.lastPrompt == "Add a login screen")
    }

    @Test func usesLatestMainThreadUsageForContext() throws {
        let meta = try meta()
        #expect(meta.contextTokens == 62_002)
        #expect(meta.model == "claude-opus-5-5[1m]")
        #expect(meta.contextWindow == 1_000_000)
        #expect(meta.lastReplyAt == TranscriptReader.parseDate("2026-10-31T10:00:09.000Z"))
        #expect(meta.cacheTTL == 3600)
    }

    @Test func recentMessagesSkipCommandsToolResultsAndSidechains() {
        let messages = TranscriptReader.recentMessages(path: url.path)
        #expect(messages.map(\.text) == [
            "Add a login screen\nwith email and password",
            "Sure, adding the **login** screen.",
            "Done.",
        ])
        #expect(messages.map(\.role) == [.user, .assistant, .assistant])
    }
}
