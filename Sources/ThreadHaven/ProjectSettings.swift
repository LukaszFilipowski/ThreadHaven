import Foundation

enum ProjectSettings {
    enum Failure: LocalizedError {
        case unexpectedFormat(String)

        var errorDescription: String? {
            switch self {
            case .unexpectedFormat(let key):
                String(localized: "Unexpected format of \(key) in the project's settings.local.json. Nothing was changed.")
            }
        }
    }

    static let mcpJsonKey = "disabledMcpjsonServers"
    static let deniedKey = "deniedMcpServers"

    static func localSettingsURL(for project: URL) -> URL {
        (gitRoot(of: project) ?? project).appendingPathComponent(".claude/settings.local.json")
    }

    static func gitRoot(of project: URL) -> URL? {
        var directory = project.standardizedFileURL
        while directory.pathComponents.count > 1 {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent(".git").path) { return directory }
            directory.deleteLastPathComponent()
        }
        return nil
    }

    static func disabledServers(in settings: [String: Any]) -> Set<String> {
        let fromMcpJson = settings[mcpJsonKey] as? [String] ?? []
        let denied = (settings[deniedKey] as? [[String: Any]] ?? []).compactMap { $0["serverName"] as? String }
        return Set(fromMcpJson + denied)
    }

    static func disabledServers(for project: URL) -> Set<String> {
        disabledServers(in: (try? load(localSettingsURL(for: project))) ?? [:])
    }

    static func setting(server name: String, fromMcpJson: Bool, enabled: Bool, in settings: [String: Any]) throws -> [String: Any] {
        var settings = settings
        if fromMcpJson {
            guard var names = (settings[mcpJsonKey] ?? [String]()) as? [String] else { throw Failure.unexpectedFormat(mcpJsonKey) }
            names.removeAll { $0 == name }
            if !enabled { names.append(name) }
            settings[mcpJsonKey] = names.isEmpty ? nil : names
        } else {
            guard var entries = (settings[deniedKey] ?? [[String: Any]]()) as? [[String: Any]] else { throw Failure.unexpectedFormat(deniedKey) }
            entries.removeAll { $0["serverName"] as? String == name }
            if !enabled { entries.append(["serverName": name]) }
            settings[deniedKey] = entries.isEmpty ? nil : entries
        }
        return settings
    }

    static func setServer(_ name: String, fromMcpJson: Bool, enabled: Bool, project: URL) throws {
        let url = localSettingsURL(for: project)
        let updated = try setting(server: name, fromMcpJson: fromMcpJson, enabled: enabled, in: load(url))
        try save(updated, to: url)
    }

    static func setPlugin(_ id: String, enabled: Bool, project: URL) async throws {
        _ = try await ClaudeCLI.command(["plugin", enabled ? "enable" : "disable", id, "--scope", "local"], in: project)
    }

    static func load(_ url: URL) throws -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: url.path), !data.isEmpty else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.unexpectedFormat("settings")
        }
        return object
    }

    static func save(_ settings: [String: Any], to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let permissions = (try? fm.attributesOfItem(atPath: url.path))?[.posixPermissions]
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
        if let permissions { try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path) }
    }
}
