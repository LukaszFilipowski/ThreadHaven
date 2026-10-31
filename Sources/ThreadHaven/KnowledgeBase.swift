import Foundation

struct KnowledgeItem: Identifiable, Hashable, Sendable {
    enum Kind: Sendable, CaseIterable {
        case claudeMd
        case memory
        case handoff
    }

    let kind: Kind
    let path: String
    var date: Date?

    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
}

enum KnowledgeBase {
    enum Failure: LocalizedError {
        case notAHandoffNote

        var errorDescription: String? {
            switch self {
            case .notAHandoffNote: String(localized: "Only handoff notes can be deleted.")
            }
        }
    }

    static let previewByteLimit = 256_000

    static func scan(
        project: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [KnowledgeItem] {
        let projectDir = project.standardizedFileURL
        let claudeDir = home.appendingPathComponent(".claude", isDirectory: true)
        var seen = Set<String>()
        let claudeMd = WorkspaceInventory.claudeMdFiles(claudeDir: claudeDir, project: projectDir)
            .filter { $0.scope == .project && seen.insert($0.path).inserted }
            .map { KnowledgeItem(kind: .claudeMd, path: $0.path) }
        return claudeMd
            + memoryFiles(project: projectDir, home: home)
            + handoffNotes(project: projectDir.path, home: home)
    }

    static func memoryFiles(project: URL, home: URL) -> [KnowledgeItem] {
        let folder = WorkspaceInventory.memoryFolder(
            claudeDir: home.appendingPathComponent(".claude", isDirectory: true),
            project: project.standardizedFileURL
        )
        return markdownFiles(in: folder)
            .sorted { a, b in
                let (left, right) = (a.lastPathComponent == "MEMORY.md", b.lastPathComponent == "MEMORY.md")
                return left != right ? left : a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
            }
            .map { KnowledgeItem(kind: .memory, path: $0.path) }
    }

    static func handoffNotes(project: String, home: URL) -> [KnowledgeItem] {
        let formatter = Handoff.fileDateFormatter()
        return markdownFiles(in: Handoff.folder(for: project, home: home))
            .map { url in
                let stamp = String(url.lastPathComponent.prefix(15))
                let date = formatter.date(from: stamp)
                    ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                return KnowledgeItem(kind: .handoff, path: url.path, date: date)
            }
            .sorted { a, b in
                let (left, right) = (a.date ?? .distantPast, b.date ?? .distantPast)
                return left != right ? left > right : a.name > b.name
            }
    }

    static func preview(path: String) -> String {
        guard let handle = FileHandle(forReadingAtPath: path) else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: previewByteLimit)) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        return data.count < previewByteLimit ? text : text + "\n…"
    }

    static func rendered(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard var result = try? AttributedString(markdown: text, options: options) else {
            return AttributedString(text)
        }
        for run in result.runs where run.link != nil && !["http", "https"].contains(run.link?.scheme?.lowercased()) {
            result[run.range].link = nil
        }
        for run in result.runs where run.imageURL != nil {
            result[run.range].imageURL = nil
        }
        return result
    }

    static func deleteNote(
        path: String,
        project: String,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let folder = Handoff.folder(for: project, home: home).resolvingSymlinksInPath()
        guard url.pathExtension == "md", url.deletingLastPathComponent().resolvingSymlinksInPath().path == folder.path else {
            throw Failure.notAHandoffNote
        }
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    private static func markdownFiles(in folder: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles
        )) ?? []
        return urls.map { folder.appendingPathComponent($0.lastPathComponent) }.filter { url in
            var isDirectory: ObjCBool = false
            return url.pathExtension == "md"
                && FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && !isDirectory.boolValue
        }
    }
}
