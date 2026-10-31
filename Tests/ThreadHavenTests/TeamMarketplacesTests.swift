import Foundation
import Testing
@testable import ThreadHaven

struct TeamMarketplacesTests {
    @Test(arguments: [
        "example-org/team-plugins",
        "example-org/team.plugins_v2",
        "https://git.example.com/example-org/team-plugins.git",
        "https://git.example.com:8443/group/sub/team-plugins",
        "git@git.example.com:example-org/team-plugins.git",
    ])
    func acceptsGitHubReposAndGitURLs(_ source: String) {
        #expect(TeamMarketplaces.isValidSource(source))
    }

    @Test(arguments: [
        "",
        "team-plugins",
        "--scope=user",
        "-example/team-plugins",
        "example-org/team-plugins; rm -rf ~",
        "example-org/team plugins",
        "example-org/..",
        "http://git.example.com/example-org/team-plugins.git",
        "https://git.example.com/../team-plugins",
        "https://user:secret@git.example.com/example-org/team-plugins.git",
        "file:///tmp/team-plugins",
        "/tmp/team-plugins",
        "git@git.example.com:example-org/team-plugins",
        "example-org/team-plugins\n--scope user",
    ])
    func rejectsEverythingElse(_ source: String) {
        #expect(!TeamMarketplaces.isValidSource(source))
    }

    @Test func buildsProjectScopedAddCommand() {
        #expect(TeamMarketplaces.addArguments(source: "example-org/team-plugins")
            == ["plugin", "marketplace", "add", "example-org/team-plugins", "--scope", "project"])
    }

    @Test func refusesInvalidSourceBeforeRunningTheCLI() async {
        await #expect(throws: TeamMarketplaces.Failure.self) {
            try await TeamMarketplaces.add(source: "--help", project: FileManager.default.temporaryDirectory)
        }
    }

    @Test func describesMarketplaceSources() {
        #expect(TeamMarketplaces.describe(["source": "github", "repo": "example-org/team-plugins"]) == "example-org/team-plugins")
        #expect(TeamMarketplaces.describe(["source": "git", "url": "https://git.example.com/x.git"]) == "https://git.example.com/x.git")
        #expect(TeamMarketplaces.describe(["source": "directory", "path": "/opt/plugins"]) == "/opt/plugins")
        #expect(TeamMarketplaces.describe(["source": "custom"]) == "custom")
        #expect(TeamMarketplaces.describe("nonsense") == "")
    }

    @Test func ignoresMalformedEntries() {
        #expect(TeamMarketplaces.marketplaces(in: ["a", "b"], origin: .project).isEmpty)
        let plugins = TeamMarketplaces.plugins(in: ["alpha@team": true, "beta@team": "yes"], origin: .project)
        #expect(plugins.map(\.name) == ["alpha@team"])
    }

    @Test func readsProjectLocalAndUserSetup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = root.appendingPathComponent("repo")
        let home = root.appendingPathComponent("home")
        defer { try? FileManager.default.removeItem(at: root) }

        try write([
            "extraKnownMarketplaces": ["team-plugins": ["source": ["source": "github", "repo": "example-org/team-plugins"]]],
            "enabledPlugins": ["review-kit@team-plugins": true, "drafts@team-plugins": false],
        ], to: project.appendingPathComponent(".claude/settings.json"))
        try write([
            "extraKnownMarketplaces": ["sandbox": ["source": ["source": "directory", "path": "/opt/sandbox"]]],
            "enabledPlugins": ["review-kit@team-plugins": false],
        ], to: project.appendingPathComponent(".claude/settings.local.json"))
        try write([
            "extraKnownMarketplaces": ["personal": ["source": ["source": "git", "url": "https://git.example.com/me/personal.git"]]],
        ], to: home.appendingPathComponent(".claude/settings.json"))
        try write([
            "personal": ["source": ["source": "git", "url": "https://git.example.com/me/personal.git"]],
            "shared-tools": ["source": ["source": "github", "repo": "example-org/shared-tools"]],
        ], to: home.appendingPathComponent(".claude/plugins/known_marketplaces.json"))

        let setup = TeamMarketplaces.scan(project: project, home: home)

        #expect(setup.marketplaces.map(\.name) == ["team-plugins", "sandbox", "personal", "shared-tools"])
        #expect(setup.marketplaces.map(\.origin) == [.project, .local, .user, .user])
        #expect(setup.marketplaces.first?.source == "example-org/team-plugins")
        #expect(setup.plugins.map(\.id) == ["project|drafts@team-plugins", "project|review-kit@team-plugins", "local|review-kit@team-plugins"])
        #expect(setup.plugins.map(\.enabled) == [false, true, false])
    }

    @Test func emptyWithoutSettings() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let setup = TeamMarketplaces.scan(project: missing, home: missing)
        #expect(setup.marketplaces.isEmpty)
        #expect(setup.plugins.isEmpty)
    }

    private func write(_ object: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: object).write(to: url)
    }
}
