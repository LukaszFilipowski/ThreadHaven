import Foundation
import Testing
@testable import ThreadHaven

struct KnowledgeBaseTests {
    let home: URL
    let project: URL

    init() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        project = root.appendingPathComponent("work/sample_app", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    }

    @discardableResult
    private func write(_ text: String, to path: String, in base: URL) throws -> URL {
        let url = base.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private var memoryPath: String {
        ".claude/projects/\(WorkspaceInventory.encodedProjectName(project.path))/memory"
    }

    private var handoffPath: String { ".threadhaven/handoffs/sample_app" }

    @Test func emptyProjectHasNoKnowledge() {
        #expect(KnowledgeBase.scan(project: project, home: home).isEmpty)
    }

    @Test func memoryListsIndexFirstThenOtherMarkdownFiles() throws {
        try write("index", to: "\(memoryPath)/MEMORY.md", in: home)
        try write("b", to: "\(memoryPath)/build-notes.md", in: home)
        try write("a", to: "\(memoryPath)/api-style.md", in: home)
        try write("x", to: "\(memoryPath)/scratch.txt", in: home)
        try write("h", to: "\(memoryPath)/.hidden.md", in: home)
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("\(memoryPath)/folder.md"), withIntermediateDirectories: true
        )
        let names = KnowledgeBase.memoryFiles(project: project, home: home).map(\.name)
        #expect(names == ["MEMORY.md", "api-style.md", "build-notes.md"])
    }

    @Test func handoffNotesAreNewestFirstWithDates() throws {
        try write("old", to: "\(handoffPath)/2026-01-02-0800-11111111.md", in: home)
        try write("new", to: "\(handoffPath)/2026-02-10-1430-22222222.md", in: home)
        try write("mid", to: "\(handoffPath)/2026-02-10-0915-33333333.md", in: home)
        try write("other", to: ".threadhaven/handoffs/another_app/2026-03-01-1000-44444444.md", in: home)
        let notes = KnowledgeBase.handoffNotes(project: project.path, home: home)
        #expect(notes.map(\.name) == [
            "2026-02-10-1430-22222222.md",
            "2026-02-10-0915-33333333.md",
            "2026-01-02-0800-11111111.md",
        ])
        let expected = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 10, hour: 14, minute: 30)))
        #expect(notes.first?.date == expected)
        #expect(notes.allSatisfy { $0.kind == .handoff })
    }

    @Test func handoffNoteWithoutDateInNameUsesModificationDate() throws {
        let url = try write("note", to: "\(handoffPath)/manual.md", in: home)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        try write("new", to: "\(handoffPath)/2026-02-10-1430-22222222.md", in: home)
        let notes = KnowledgeBase.handoffNotes(project: project.path, home: home)
        #expect(notes.map(\.name) == ["2026-02-10-1430-22222222.md", "manual.md"])
        #expect(notes.last?.date == date)
    }

    @Test func handoffNotesMatchTheFolderUsedBySave() throws {
        let saved = try Handoff.save(note: "# Note", sessionId: "abcdef12-0000", cwd: project.path, home: home)
        #expect(KnowledgeBase.handoffNotes(project: project.path, home: home).map(\.path) == [saved.path])
    }

    @Test func scanGroupsProjectClaudeMdMemoryAndNotes() throws {
        try write("user", to: ".claude/CLAUDE.md", in: home)
        try write("project", to: "CLAUDE.md", in: project)
        try write("local", to: "CLAUDE.local.md", in: project)
        try write("index", to: "\(memoryPath)/MEMORY.md", in: home)
        try write("note", to: "\(handoffPath)/2026-02-10-1430-22222222.md", in: home)
        let items = KnowledgeBase.scan(project: project, home: home)
        #expect(items.map(\.kind) == [.claudeMd, .claudeMd, .memory, .handoff])
        #expect(Set(items.prefix(2).map(\.name)) == ["CLAUDE.md", "CLAUDE.local.md"])
        #expect(!items.contains { $0.path.hasPrefix(home.appendingPathComponent(".claude/CLAUDE.md").path) })
    }

    @Test func deleteRemovesOnlyHandoffNotes() throws {
        let note = try write("note", to: "\(handoffPath)/2026-02-10-1430-22222222.md", in: home)
        let memory = try write("index", to: "\(memoryPath)/MEMORY.md", in: home)
        let claudeMd = try write("project", to: "CLAUDE.md", in: project)
        let elsewhere = try write("other", to: ".threadhaven/handoffs/another_app/2026-03-01-1000-44444444.md", in: home)
        for url in [memory, claudeMd, elsewhere] {
            #expect(throws: KnowledgeBase.Failure.self) {
                try KnowledgeBase.deleteNote(path: url.path, project: project.path, home: home)
            }
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
        #expect(throws: KnowledgeBase.Failure.self) {
            try KnowledgeBase.deleteNote(path: "\(note.deletingLastPathComponent().path)/../../../../work/sample_app/CLAUDE.md", project: project.path, home: home)
        }
        try KnowledgeBase.deleteNote(path: note.path, project: project.path, home: home)
        #expect(!FileManager.default.fileExists(atPath: note.path))
    }

    @Test func previewIsCappedAndRenderingDropsUnsafeLinks() throws {
        let url = try write(String(repeating: "a", count: KnowledgeBase.previewByteLimit + 10), to: "big.md", in: home)
        #expect(KnowledgeBase.preview(path: url.path).count == KnowledgeBase.previewByteLimit + 2)
        #expect(KnowledgeBase.preview(path: "/nonexistent/file.md").isEmpty)
        let text = KnowledgeBase.rendered("[web](https://example.com) [local](file:///etc/hosts) ![img](https://example.com/a.png)")
        let links = text.runs.compactMap(\.link)
        #expect(links == [URL(string: "https://example.com")!])
        #expect(text.runs.allSatisfy { $0.imageURL == nil })
    }
}
