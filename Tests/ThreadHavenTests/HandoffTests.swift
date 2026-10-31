import Foundation
import Testing
@testable import ThreadHaven

struct HandoffTests {
    let path = Bundle.module.url(forResource: "handoff", withExtension: "jsonl", subdirectory: "Fixtures")!.path

    @Test func digestKeepsPromptsRepliesAndToolCalls() {
        #expect(Handoff.digest(path: path) == """
        User: Fix the failing date parser test
        Assistant: Let me look at the parser.
        Tool: Read /Users/dev/project/Sources/DateParser.swift
        Tool: Bash swift test --filter DateParserTests && echo done
        Tool: TodoWrite
        Assistant: The test passes now.
        """)
    }

    @Test func digestKeepsMostRecentContentWithinBudget() {
        let digest = Handoff.digest(path: path, budget: 60)
        #expect(digest == """
        \(Handoff.cutMarker)
        Tool: TodoWrite
        Assistant: The test passes now.
        """)
    }

    @Test func digestTruncatesLongToolInput() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jsonl")
        let command = String(repeating: "a", count: 500)
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"\#(command)"}}]}}"#
        try Data(line.utf8).write(to: file)
        #expect(Handoff.digest(path: file.path) == "Tool: Bash " + String(repeating: "a", count: 200) + "…")
    }

    @Test func digestOfMissingFileIsEmpty() {
        #expect(Handoff.digest(path: "/nonexistent/session.jsonl").isEmpty)
    }

    @Test func saveWritesNoteIntoProjectFolder() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 9, minute: 5)))
        let url = try Handoff.save(
            note: "# Handoff",
            sessionId: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            cwd: "/Users/dev/project",
            home: home,
            date: date
        )
        #expect(url.path == home.appendingPathComponent(".threadhaven/handoffs/project/2026-03-07-0905-aaaaaaaa.md").path)
        #expect(try String(contentsOf: url, encoding: .utf8) == "# Handoff")
    }
}
