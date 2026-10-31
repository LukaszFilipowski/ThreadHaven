import Foundation

struct TeamMarketplace: Identifiable, Hashable, Sendable {
    enum Origin: String, Sendable, CaseIterable {
        case project
        case local
        case user
    }

    let name: String
    let source: String
    let origin: Origin

    var id: String { "\(origin.rawValue)|\(name)" }
}

struct TeamPlugin: Identifiable, Hashable, Sendable {
    enum Origin: String, Sendable, CaseIterable {
        case project
        case local
    }

    let name: String
    let enabled: Bool
    let origin: Origin

    var id: String { "\(origin.rawValue)|\(name)" }
}

struct TeamSetup: Sendable {
    var marketplaces: [TeamMarketplace] = []
    var plugins: [TeamPlugin] = []
}

enum TeamMarketplaces {
    static let marketplacesKey = "extraKnownMarketplaces"
    static let pluginsKey = "enabledPlugins"

    static func isValidSource(_ source: String) -> Bool {
        let github = #/[A-Za-z0-9][A-Za-z0-9-]{0,38}\/[A-Za-z0-9._-]{1,100}/#
        let https = #/https:\/\/[A-Za-z0-9.-]+(?::[0-9]{1,5})?(?:\/[A-Za-z0-9._~-]+)+/#
        let ssh = #/git@[A-Za-z0-9.-]+:[A-Za-z0-9._-]+(?:\/[A-Za-z0-9._-]+)*\.git/#
        guard source.wholeMatch(of: github) != nil
            || source.wholeMatch(of: https) != nil
            || source.wholeMatch(of: ssh) != nil
        else { return false }
        let pieces = source.split(whereSeparator: { "/:".contains($0) })
        return !pieces.contains { $0 == "." || $0 == ".." }
    }

    static func addArguments(source: String) -> [String] {
        ["plugin", "marketplace", "add", source, "--scope", "project"]
    }

    static func add(source: String, project: URL) async throws -> String {
        guard isValidSource(source) else { throw Failure.invalidSource }
        return try await ClaudeCLI.command(addArguments(source: source), in: projectRoot(of: project))
    }

    enum Failure: LocalizedError {
        case invalidSource

        var errorDescription: String? {
            String(localized: "Enter a GitHub repository as owner/repo or a git URL.")
        }
    }

    static func projectRoot(of project: URL) -> URL {
        ProjectSettings.gitRoot(of: project) ?? project.standardizedFileURL
    }

    static func sharedSettingsURL(for project: URL) -> URL {
        projectRoot(of: project).appendingPathComponent(".claude/settings.json")
    }

    static func scan(
        project: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> TeamSetup {
        let shared = settings(at: sharedSettingsURL(for: project))
        let local = settings(at: ProjectSettings.localSettingsURL(for: project))
        let claudeDir = home.appendingPathComponent(".claude", isDirectory: true)
        let user = settings(at: claudeDir.appendingPathComponent("settings.json"))
        let known = settings(at: claudeDir.appendingPathComponent("plugins/known_marketplaces.json"))

        var found = marketplaces(in: shared[marketplacesKey], origin: .project)
            + marketplaces(in: local[marketplacesKey], origin: .local)
        let userEntries = marketplaces(in: user[marketplacesKey], origin: .user)
            + marketplaces(in: known, origin: .user)
        var seenUser = Set<String>()
        found += userEntries.filter { seenUser.insert($0.name).inserted }

        return TeamSetup(
            marketplaces: found,
            plugins: plugins(in: shared[pluginsKey], origin: .project) + plugins(in: local[pluginsKey], origin: .local)
        )
    }

    static func marketplaces(in value: Any?, origin: TeamMarketplace.Origin) -> [TeamMarketplace] {
        guard let entries = value as? [String: Any] else { return [] }
        return entries.keys.sorted().map { name in
            let entry = entries[name] as? [String: Any]
            return TeamMarketplace(name: name, source: describe(entry?["source"]), origin: origin)
        }
    }

    static func plugins(in value: Any?, origin: TeamPlugin.Origin) -> [TeamPlugin] {
        guard let entries = value as? [String: Any] else { return [] }
        return entries.keys.sorted().compactMap { name in
            guard let enabled = entries[name] as? Bool else { return nil }
            return TeamPlugin(name: name, enabled: enabled, origin: origin)
        }
    }

    static func describe(_ source: Any?) -> String {
        guard let source = source as? [String: Any] else { return "" }
        for key in ["repo", "url", "path", "package"] {
            if let value = source[key] as? String, !value.isEmpty { return value }
        }
        return source["source"] as? String ?? ""
    }

    private static func settings(at url: URL) -> [String: Any] {
        (try? ProjectSettings.load(url)) ?? [:]
    }
}
