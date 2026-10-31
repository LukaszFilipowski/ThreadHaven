import Foundation
import Testing
@testable import ThreadHaven

struct WorkspaceInventoryTests {
    let root: URL
    let home: URL
    let project: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        project = root.appendingPathComponent("work/demo_app", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    }

    private func write(_ text: String, to path: String, in base: URL) throws {
        let url = base.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func item(_ kind: InventoryItem.Kind, _ name: String, in items: [InventoryItem]) throws -> InventoryItem {
        try #require(items.first { $0.kind == kind && $0.name == name })
    }

    private func skill(name: String, description: String) -> String {
        "---\nname: \(name)\ndescription: \(description)\n---\n\n" + String(repeating: "Body text. ", count: 500)
    }

    @Test func emptyHomeYieldsNothing() {
        #expect(WorkspaceInventory.scan(project: project, home: home).isEmpty)
        #expect(WorkspaceInventory.scan(home: home).isEmpty)
    }

    @Test func claudeMdFilesCountWholeContent() throws {
        try write(String(repeating: "a", count: 400), to: ".claude/CLAUDE.md", in: home)
        try write(String(repeating: "b", count: 81), to: "CLAUDE.md", in: project)
        try write("local", to: "CLAUDE.local.md", in: project)
        try write("nested", to: ".claude/CLAUDE.md", in: project)
        let items = WorkspaceInventory.scan(project: project, home: home).filter { $0.kind == .claudeMd }
        #expect(items.map(\.scope) == [.user, .project, .project, .project])
        #expect(items[0].estimatedTokens == 100)
        #expect(items.first { $0.path == project.appendingPathComponent("CLAUDE.md").path }?.estimatedTokens == 21)
        #expect(items.allSatisfy { $0.enabled == true })
    }

    @Test func memoryUsesEncodedProjectPathAndLineLimit() throws {
        let encoded = WorkspaceInventory.encodedProjectName(project.path)
        #expect(!encoded.contains("/"))
        #expect(!encoded.contains("_"))
        let lines = (1...300).map { _ in "abc" }.joined(separator: "\n")
        try write(lines, to: ".claude/projects/\(encoded)/memory/MEMORY.md", in: home)
        let memory = try item(.memory, "MEMORY.md", in: WorkspaceInventory.scan(project: project, home: home))
        #expect(memory.scope == .project)
        #expect(memory.estimatedTokens == WorkspaceInventory.estimatedTokens(bytes: 200 * 4 - 1))
    }

    @Test func encodedProjectNameReplacesEveryNonAlphanumeric() {
        #expect(WorkspaceInventory.encodedProjectName("/Users/dev/my_app/.config") == "-Users-dev-my-app--config")
    }

    @Test func skillsCountOnlyFrontmatterListing() throws {
        try write(skill(name: "example-skill", description: "Does example things"), to: ".claude/skills/example-skill/SKILL.md", in: home)
        try write("No frontmatter", to: ".claude/skills/plain/SKILL.md", in: home)
        try write(skill(name: "team-skill", description: "Shared"), to: ".claude/skills/team/SKILL.md", in: project)
        try write("ignored", to: ".claude/skills/notes.md", in: home)
        let items = WorkspaceInventory.scan(project: project, home: home)
        let example = try item(.skill, "example-skill", in: items)
        #expect(example.scope == .user)
        #expect(example.estimatedTokens == WorkspaceInventory.estimatedTokens(bytes: "example-skill: Does example things".utf8.count))
        #expect(try item(.skill, "plain", in: items).estimatedTokens == 2)
        #expect(try item(.skill, "team-skill", in: items).scope == .project)
        #expect(items.filter { $0.kind == .skill }.count == 3)
    }

    @Test func projectInHomeIsNotCountedTwice() throws {
        try write("rules", to: ".claude/CLAUDE.md", in: home)
        try write(skill(name: "example-skill", description: "Once"), to: ".claude/skills/example-skill/SKILL.md", in: home)
        let items = WorkspaceInventory.scan(project: home, home: home)
        #expect(items.filter { $0.kind == .claudeMd }.count == 1)
        #expect(items.filter { $0.kind == .skill }.count == 1)
    }

    @Test func agentsAndCommandsUseFileNamesAsFallback() throws {
        try write("---\ndescription: Reviews code\n---\nPrompt", to: ".claude/agents/reviewer.md", in: home)
        try write("Just a prompt", to: ".claude/commands/ship.md", in: project)
        let items = WorkspaceInventory.scan(project: project, home: home)
        #expect(try item(.agent, "reviewer", in: items).scope == .user)
        #expect(try item(.command, "ship", in: items).scope == .project)
    }

    @Test func frontmatterHandlesFoldedAndQuotedValues() {
        let fields = WorkspaceInventory.frontmatter("---\nname: \"quoted\"\ndescription: >\n  first line\n  second line\nmetadata:\n  version: 1\n---\nbody")
        #expect(fields["name"] == "quoted")
        #expect(fields["description"] == "first line second line")
        #expect(WorkspaceInventory.frontmatter("no frontmatter").isEmpty)
    }

    @Test func mcpServersReportNamesOnly() throws {
        let config = """
        {"mcpServers": {"docs-server": {"command": "docs", "env": {"TOKEN": "secret"}}},
         "projects": {"\(project.path)": {
            "mcpServers": {"local-db": {"command": "db"}},
            "disabledMcpServers": ["docs-server"],
            "enabledMcpjsonServers": ["shared-search"]}}}
        """
        try write(config, to: ".claude.json", in: home)
        try write(#"{"mcpServers": {"shared-search": {}, "pending-server": {}}}"#, to: ".mcp.json", in: project)
        try write(#"{"disabledMcpjsonServers": ["rejected-server"]}"#, to: ".claude/settings.local.json", in: project)
        let items = WorkspaceInventory.scan(project: project, home: home).filter { $0.kind == .mcpServer }
        #expect(items.map(\.name) == ["docs-server", "local-db", "pending-server", "shared-search"])
        #expect(items.map(\.enabled) == [false, true, nil, true])
        #expect(items.map(\.scope) == [.user, .project, .project, .project])
        #expect(items.allSatisfy { $0.estimatedTokens == nil })
    }

    @Test func pluginsExposeTheirComponentsAndEnabledState() throws {
        let installA = root.appendingPathComponent("plugins/alpha/1.0.0", isDirectory: true)
        let installB = root.appendingPathComponent("plugins/beta/2.0.0", isDirectory: true)
        let installed = """
        {"version": 2, "plugins": {
          "alpha@market": [{"scope": "user", "installPath": "\(installA.path)"}],
          "beta@market": [{"scope": "user", "installPath": "\(installB.path)"}],
          "gamma@market": [{"scope": "project", "projectPath": "/elsewhere", "installPath": "/missing"}]}}
        """
        try write(installed, to: ".claude/plugins/installed_plugins.json", in: home)
        try write(#"{"enabledPlugins": {"alpha@market": true, "beta@market": false}}"#, to: ".claude/settings.json", in: home)
        try write(#"{"name": "alpha", "skills": ["./extra/skills"]}"#, to: ".claude-plugin/plugin.json", in: installA)
        try write(skill(name: "draw", description: "Draws"), to: "skills/draw/SKILL.md", in: installA)
        try write(skill(name: "paint", description: "Paints"), to: "extra/skills/paint/SKILL.md", in: installA)
        try write("---\nname: helper\ndescription: Helps\n---\n", to: "agents/helper.md", in: installA)
        try write(#"{"mcpServers": {"search": {}}}"#, to: ".mcp.json", in: installA)
        try write(#"{"name": "beta", "mcpServers": {"inline": {}}}"#, to: ".claude-plugin/plugin.json", in: installB)
        try write(skill(name: "idle", description: "Off"), to: "skills/idle/SKILL.md", in: installB)

        let items = WorkspaceInventory.scan(project: project, home: home)
        #expect(try item(.plugin, "alpha@market", in: items).enabled == true)
        #expect(try item(.plugin, "beta@market", in: items).enabled == false)
        #expect(!items.contains { $0.name == "gamma@market" })
        #expect(try item(.skill, "alpha:draw", in: items).scope == .plugin)
        #expect(try item(.skill, "alpha:paint", in: items).enabled == true)
        #expect(try item(.agent, "alpha:helper", in: items).estimatedTokens == 4)
        #expect(try item(.mcpServer, "alpha:search", in: items).estimatedTokens == nil)
        #expect(try item(.mcpServer, "beta:inline", in: items).enabled == false)
        #expect(try item(.skill, "beta:idle", in: items).enabled == false)
    }

    @Test func baselineSkipsDisabledItems() {
        let items = [
            InventoryItem(kind: .claudeMd, name: "CLAUDE.md", scope: .user, path: "/a", enabled: true, estimatedTokens: 100),
            InventoryItem(kind: .skill, name: "off", scope: .plugin, path: "/b", enabled: false, estimatedTokens: 50),
            InventoryItem(kind: .skill, name: "on", scope: .user, path: "/c", enabled: nil, estimatedTokens: 7),
            InventoryItem(kind: .mcpServer, name: "docs-server", scope: .user, path: "/d", enabled: true),
        ]
        #expect(WorkspaceInventory.baselineTokens(of: items) == 107)
    }

    @Test func malformedFilesAreSkipped() throws {
        try write("{not json", to: ".claude.json", in: home)
        try write("[1, 2]", to: ".claude/plugins/installed_plugins.json", in: home)
        try write(#"{"enabledPlugins": "yes"}"#, to: ".claude/settings.json", in: home)
        try write(#"{"mcpServers": ["a"]}"#, to: ".mcp.json", in: project)
        try FileManager.default.createDirectory(at: project.appendingPathComponent("CLAUDE.md"), withIntermediateDirectories: true)
        #expect(WorkspaceInventory.scan(project: project, home: home).isEmpty)
    }
}

struct InventoryGroupingTests {
    private func item(_ kind: InventoryItem.Kind, _ name: String, tokens: Int?, enabled: Bool? = true) -> InventoryItem {
        InventoryItem(kind: kind, name: name, scope: .user, path: "/tmp/\(name)", enabled: enabled, estimatedTokens: tokens)
    }

    @Test func groupsFollowKindOrderAndSortByTokens() {
        let groups = WorkspaceInventory.grouped([
            item(.mcpServer, "beta", tokens: nil),
            item(.skill, "small", tokens: 10),
            item(.claudeMd, "CLAUDE.md", tokens: 300),
            item(.skill, "unknown", tokens: nil),
            item(.skill, "large", tokens: 90),
            item(.skill, "alpha", tokens: 10),
            item(.mcpServer, "alpha", tokens: nil),
        ])
        #expect(groups.map(\.kind) == [.claudeMd, .skill, .mcpServer])
        #expect(groups[1].items.map(\.name) == ["large", "alpha", "small", "unknown"])
        #expect(groups[2].items.map(\.name) == ["alpha", "beta"])
    }

    @Test func groupTotalsSkipDisabledItems() {
        let groups = WorkspaceInventory.grouped([
            item(.command, "on", tokens: 40),
            item(.command, "off", tokens: 25, enabled: false),
            item(.command, "default", tokens: 5, enabled: nil),
        ])
        #expect(groups.first?.tokens == 45)
    }
}
