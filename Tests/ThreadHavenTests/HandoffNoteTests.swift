import Foundation
import Testing
@testable import ThreadHaven
import ThreadHavenCore

struct HandoffNoteTests {
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
