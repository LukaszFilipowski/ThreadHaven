import Foundation
import Testing
@testable import ThreadHaven

struct HookEventTests {
    private func decode(_ json: String) throws -> HookLine {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(HookLine.self, from: Data(json.utf8))
    }

    @Test func decodesNotificationLine() throws {
        let line = try decode(#"""
        {"ts":1790000000,"term":"Apple_Terminal","bundle":"com.apple.Terminal","tty":"ttys005","event":{"session_id":"abc","hook_event_name":"Notification","cwd":"/tmp/x","transcript_path":"/tmp/x.jsonl","message":"Claude needs your permission to use Bash","notification_type":"permission_prompt"}}
        """#)
        #expect(line.event.sessionId == "abc")
        #expect(line.event.hookEventName == "Notification")
        #expect(line.event.notificationType == "permission_prompt")
        #expect(line.tty == "ttys005")
    }

    @Test func mergeKeepsKnownValuesWhenLineIsSparse() throws {
        var info = LiveInfo(updatedAt: .distantPast)
        info.merge(try decode(#"{"ts":1,"term":"iTerm.app","bundle":"","tty":"ttys001","event":{"session_id":"a","hook_event_name":"SessionStart","cwd":"/a"}}"#))
        info.merge(try decode(#"{"ts":2,"term":"","bundle":"","tty":"","event":{"session_id":"a","hook_event_name":"PostToolUse"}}"#))
        #expect(info.term == "iTerm.app")
        #expect(info.tty == "ttys001")
        #expect(info.cwd == "/a")
        #expect(info.isInteractive)
        #expect(info.updatedAt == Date(timeIntervalSince1970: 2))
    }

    @Test func backgroundSessionsAreNotInteractive() {
        var info = LiveInfo(updatedAt: .now)
        info.tty = "??"
        #expect(!info.isInteractive)
    }
}
