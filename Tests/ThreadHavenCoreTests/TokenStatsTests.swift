import Foundation
import Testing
@testable import ThreadHavenCore

struct TokenStatsTests {
    let stats = TokenStats.analyze(
        url: Bundle.module.url(forResource: "token-stats", withExtension: "jsonl", subdirectory: "Fixtures")!
    )

    @Test func countsEachMessageIdOnce() {
        #expect(stats.turns == 4)
        #expect(stats.outputTokens == 180)
        #expect(stats.cacheReadTokens == 70_000)
        #expect(stats.cacheWriteTokens == 97_000)
    }

    @Test func tracksContextOfMainThreadOnly() {
        #expect(stats.baselineContext == 30_010)
        #expect(stats.currentContext == 65_002)
        #expect(stats.peakContext == 65_002)
    }

    @Test func detectsColdCacheRebuilds() {
        #expect(stats.coldRebuilds == 1)
        #expect(stats.coldRebuildTokens == 40_000)
    }

    @Test func ranksHeaviestToolResults() {
        #expect(stats.heaviestToolResults == [
            .init(tool: "WebFetch", label: "https://example.com/docs", tokens: 500),
            .init(tool: "Bash", label: "swift build", tokens: 200),
            .init(tool: "Read", label: "/Users/dev/projects/demo/App.swift", tokens: 100),
            .init(tool: "Glob", label: "**/*.swift", tokens: 50),
            .init(tool: "Edit", label: "/Users/dev/projects/demo/Login.swift", tokens: 30),
        ])
    }

    @Test func readsLastReplyDate() throws {
        let date = try #require(stats.lastReply)
        #expect(date.timeIntervalSince1970 == 1_793_442_660.25)
    }

    @Test func returnsEmptyStatsForMissingFile() {
        #expect(TokenStats.analyze(url: URL(fileURLWithPath: "/nonexistent.jsonl")) == TokenStats())
    }
}
