import Foundation
import Testing
@testable import ThreadHaven

struct HookScriptTests {
    private func run(_ payload: String, home: URL) throws {
        let script = home.appendingPathComponent("hook.sh")
        try HookInstaller.script.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        let input = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path]
        process.environment = ["HOME": home.path, "TERM_PROGRAM": "Apple_Terminal", "PATH": "/usr/bin:/bin"]
        process.standardInput = input
        try process.run()
        input.fileHandleForWriting.write(Data(payload.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
    }

    private func tempHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func events(in home: URL) throws -> [[String: Any]] {
        let data = try Data(contentsOf: home.appendingPathComponent(".threadhaven/events.jsonl"))
        return try data.split(separator: 0x0A).map {
            try #require(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any])
        }
    }

    @Test func appendsOneJSONLinePerEvent() throws {
        let home = try tempHome()
        try run(#"{"session_id":"s1","hook_event_name":"Stop","last_assistant_message":"Done\nall good"}"#, home: home)
        let lines = try events(in: home)
        #expect(lines.count == 1)
        #expect(lines[0]["term"] as? String == "Apple_Terminal")
        let event = try #require(lines[0]["event"] as? [String: Any])
        #expect(event["session_id"] as? String == "s1")
    }

    @Test func shrinksPostToolUsePayload() throws {
        let home = try tempHome()
        let big = String(repeating: "x", count: 50_000)
        try run(#"{"session_id":"s2","hook_event_name":"PostToolUse","tool_response":"\#(big)"}"#, home: home)
        let event = try #require(try events(in: home).first?["event"] as? [String: Any])
        #expect(event.count == 2)
        #expect(event["session_id"] as? String == "s2")
    }

    @Test func ignoresEmptyInput() throws {
        let home = try tempHome()
        try run("", home: home)
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(".threadhaven/events.jsonl").path))
    }
}
