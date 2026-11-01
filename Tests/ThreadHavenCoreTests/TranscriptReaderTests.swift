import Foundation
import Testing
@testable import ThreadHavenCore

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

    @Test func baselineContextComesFromFirstMainThreadReply() throws {
        #expect(try meta().baselineContext == 45_010)
    }

    @Test func baselineContextSkipsSidechainsAndStaysNilWithoutReplies() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let user = #"{"type":"user","isSidechain":false,"message":{"role":"user","content":"Hello"},"cwd":"/tmp/demo"}"#
        let sidechain = #"{"type":"assistant","isSidechain":true,"message":{"usage":{"input_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}"#
        let reply = #"{"type":"assistant","isSidechain":false,"message":{"usage":{"input_tokens":3,"cache_read_input_tokens":0,"cache_creation_input_tokens":21000}}}"#
        let later = #"{"type":"assistant","isSidechain":false,"message":{"usage":{"input_tokens":1,"cache_read_input_tokens":30000,"cache_creation_input_tokens":500}}}"#

        func readMeta(_ lines: [String]) throws -> TranscriptMeta {
            let url = dir.appendingPathComponent(UUID().uuidString + ".jsonl")
            try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
            return TranscriptReader.readMeta(url: url, stamp: try #require(TranscriptReader.stamp(of: url)))
        }

        let replied = try readMeta([user, sidechain, reply, later])
        #expect(replied.baselineContext == 21_003)
        #expect(replied.contextTokens == 30_501)
        #expect(try readMeta([user]).baselineContext == nil)
    }

    @Test func recentMessagesShowCommandsAndSkipToolResultsAndSidechains() {
        let messages = TranscriptReader.recentMessages(path: url.path)
        #expect(messages.map(\.text) == [
            "/clear",
            "Add a login screen\nwith email and password",
            "Sure, adding the **login** screen.",
            "Done.",
        ])
        #expect(messages.map(\.role) == [.user, .user, .assistant, .assistant])
    }

    @Test func stripsTaggedBlocksFromPrompts() {
        let text = "<system-reminder>\nignore\n</system-reminder>\nFix the build<ide_selection a=\"1\">x</ide_selection>"
        #expect(TranscriptReader.withoutTaggedBlocks(text).trimmingCharacters(in: .whitespacesAndNewlines) == "Fix the build")
    }

    @Test func summarizesToolCalls() {
        let block: [String: Any] = ["type": "tool_use", "name": "Bash", "input": ["command": "swift test\n--verbose", "description": "Run tests"]]
        #expect(TranscriptReader.toolSummary(block) == "Bash · Run tests")
        #expect(TranscriptReader.toolSummary(["name": "Read", "input": ["file_path": "/tmp/a.swift"]]) == "Read · /tmp/a.swift")
    }

    @Test func turnsLocalCommandOutputIntoOutputMessages() {
        let output = TranscriptReader.commandMessage("<local-command-stdout>Compacted</local-command-stdout>", id: "x", date: nil)
        #expect(output?.role == .output)
        #expect(output?.text == "Compacted")
        let command = TranscriptReader.commandMessage("<command-name>/model</command-name><command-args>opus</command-args>", id: "y", date: nil)
        #expect(command?.text == "/model opus")
    }

    @Test func recognizesBackgroundSessions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sdk = dir.appendingPathComponent("sdk.jsonl")
        try Data(#"{"type":"user","entrypoint":"sdk-cli"}"#.utf8).write(to: sdk)
        let cli = dir.appendingPathComponent("cli.jsonl")
        try Data(#"{"type":"user","entrypoint":"cli"}"#.utf8).write(to: cli)
        #expect(!TranscriptReader.looksInteractive(sdk))
        #expect(TranscriptReader.looksInteractive(cli))
        #expect(TranscriptReader.looksInteractive(url))
    }
}
