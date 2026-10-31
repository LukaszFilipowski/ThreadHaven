import Foundation
import Testing
@testable import ThreadHaven

struct ProjectSettingsTests {
    @Test func disablesAndEnablesMcpJsonServers() throws {
        let off = try ProjectSettings.setting(server: "docs", fromMcpJson: true, enabled: false, in: ["model": "sonnet"])
        #expect(off["disabledMcpjsonServers"] as? [String] == ["docs"])
        #expect(off["model"] as? String == "sonnet")
        let on = try ProjectSettings.setting(server: "docs", fromMcpJson: true, enabled: true, in: off)
        #expect(on["disabledMcpjsonServers"] == nil)
    }

    @Test func deniesOtherServersByName() throws {
        let settings: [String: Any] = ["deniedMcpServers": [["serverUrl": "https://example.com/mcp"]]]
        let off = try ProjectSettings.setting(server: "search", fromMcpJson: false, enabled: false, in: settings)
        #expect(ProjectSettings.disabledServers(in: off) == ["search"])
        #expect((off["deniedMcpServers"] as? [[String: Any]])?.count == 2)
        let on = try ProjectSettings.setting(server: "search", fromMcpJson: false, enabled: true, in: off)
        #expect((on["deniedMcpServers"] as? [[String: Any]])?.count == 1)
    }

    @Test func refusesUnexpectedFormat() {
        #expect(throws: ProjectSettings.Failure.self) {
            try ProjectSettings.setting(server: "x", fromMcpJson: true, enabled: false, in: ["disabledMcpjsonServers": "x"])
        }
    }

    @Test func usesTheRepositoryRootInsideGit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = root.appendingPathComponent("packages/app")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        #expect(ProjectSettings.localSettingsURL(for: nested).path.hasSuffix(root.lastPathComponent + "/.claude/settings.local.json"))
    }

    @Test func savesAndReadsBack() throws {
        let project = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try ProjectSettings.setServer("docs", fromMcpJson: false, enabled: false, project: project)
        #expect(ProjectSettings.disabledServers(for: project) == ["docs"])
    }
}
