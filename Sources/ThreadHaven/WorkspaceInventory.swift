import Foundation

struct InventoryItem: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable, CaseIterable {
        case claudeMd
        case memory
        case skill
        case command
        case agent
        case mcpServer
        case plugin
    }

    enum Scope: String, Sendable {
        case user
        case project
        case plugin
    }

    let kind: Kind
    let name: String
    let scope: Scope
    let path: String
    var enabled: Bool?
    var estimatedTokens: Int?

    var id: String { "\(kind.rawValue)|\(scope.rawValue)|\(name)|\(path)" }
}

enum WorkspaceInventory {
    static let memoryLineLimit = 200

    static func scan(
        project: URL? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [InventoryItem] {
        let claudeDir = home.appendingPathComponent(".claude", isDirectory: true)
        let projectDir = project?.standardizedFileURL
        let settings = mergedSettings(claudeDir: claudeDir, project: projectDir)
        let globalConfigURL = home.appendingPathComponent(".claude.json")
        let globalConfig = json(at: globalConfigURL) ?? [:]
        let projectConfig = projectDir.flatMap { (globalConfig["projects"] as? [String: Any])?[$0.path] as? [String: Any] } ?? [:]

        var items: [InventoryItem] = []
        items += claudeMdFiles(claudeDir: claudeDir, project: projectDir)
        if let projectDir { items += memory(claudeDir: claudeDir, project: projectDir) }
        items += markdownComponents(in: claudeDir, scope: .user, prefix: nil, enabled: nil)
        if let projectDir {
            let dotClaude = projectDir.appendingPathComponent(".claude", isDirectory: true)
            items += markdownComponents(in: dotClaude, scope: .project, prefix: nil, enabled: nil)
        }
        items += mcpServers(
            config: globalConfig, configPath: globalConfigURL.path,
            projectConfig: projectConfig, settings: settings, project: projectDir
        )
        items += plugins(claudeDir: claudeDir, settings: settings, project: projectDir)
        var seen = Set<String>()
        return items.filter { seen.insert("\($0.kind.rawValue)|\($0.name)|\($0.path)").inserted }
    }

    static func baselineTokens(of items: [InventoryItem]) -> Int {
        items.filter { $0.enabled != false }.compactMap(\.estimatedTokens).reduce(0, +)
    }

    static func estimatedTokens(bytes: Int) -> Int {
        (bytes + 3) / 4
    }

    static func encodedProjectName(_ path: String) -> String {
        String(path.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
    }

    private static func claudeMdFiles(claudeDir: URL, project: URL?) -> [InventoryItem] {
        var candidates: [(URL, InventoryItem.Scope)] = [(claudeDir.appendingPathComponent("CLAUDE.md"), .user)]
        if let project {
            candidates.append((project.appendingPathComponent(".claude/CLAUDE.md"), .project))
            let components = project.pathComponents
            for depth in stride(from: components.count, through: 1, by: -1) {
                let dir = URL(fileURLWithPath: NSString.path(withComponents: Array(components.prefix(depth))), isDirectory: true)
                candidates.append((dir.appendingPathComponent("CLAUDE.md"), .project))
                candidates.append((dir.appendingPathComponent("CLAUDE.local.md"), .project))
            }
        }
        return candidates.compactMap { url, scope in
            guard let data = read(url) else { return nil }
            return InventoryItem(
                kind: .claudeMd, name: url.lastPathComponent, scope: scope, path: url.path,
                enabled: true, estimatedTokens: estimatedTokens(bytes: data.count)
            )
        }
    }

    private static func memory(claudeDir: URL, project: URL) -> [InventoryItem] {
        let url = claudeDir
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(encodedProjectName(project.path), isDirectory: true)
            .appendingPathComponent("memory/MEMORY.md")
        guard let data = read(url) else { return [] }
        let loaded = String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(memoryLineLimit)
            .joined(separator: "\n")
        return [InventoryItem(
            kind: .memory, name: "MEMORY.md", scope: .project, path: url.path,
            enabled: true, estimatedTokens: estimatedTokens(bytes: loaded.utf8.count)
        )]
    }

    private static func markdownComponents(
        in root: URL,
        scope: InventoryItem.Scope,
        prefix: String?,
        enabled: Bool?,
        manifest: [String: Any] = [:]
    ) -> [InventoryItem] {
        let kinds: [(String, InventoryItem.Kind)] = [("skills", .skill), ("commands", .command), ("agents", .agent)]
        return kinds.flatMap { folder, kind in
            let declared = paths(manifest[folder]).map { root.appendingPathComponent($0).standardizedFileURL }
            let dirs = ([root.appendingPathComponent(folder, isDirectory: true).standardizedFileURL] + declared)
                .reduce(into: [URL]()) { unique, url in
                    if !unique.contains(where: { $0.path == url.path }) { unique.append(url) }
                }
            return dirs.flatMap { componentFiles(in: $0, kind: kind) }.compactMap { url in
                component(at: url, kind: kind, scope: scope, prefix: prefix, enabled: enabled)
            }
        }
    }

    private static func componentFiles(in dir: URL, kind: InventoryItem.Kind) -> [URL] {
        let fm = FileManager.default
        if kind == .skill {
            let own = dir.appendingPathComponent("SKILL.md")
            if fm.fileExists(atPath: own.path) { return [own] }
            return children(of: dir)
                .map { $0.appendingPathComponent("SKILL.md") }
                .filter { fm.fileExists(atPath: $0.path) }
        }
        if dir.pathExtension == "md", fm.fileExists(atPath: dir.path) { return [dir] }
        return children(of: dir).filter { $0.pathExtension == "md" }
    }

    private static func component(
        at url: URL,
        kind: InventoryItem.Kind,
        scope: InventoryItem.Scope,
        prefix: String?,
        enabled: Bool?
    ) -> InventoryItem? {
        guard let data = read(url) else { return nil }
        let fields = frontmatter(String(decoding: data, as: UTF8.self))
        let fallback = kind == .skill
            ? url.deletingLastPathComponent().lastPathComponent
            : url.deletingPathExtension().lastPathComponent
        let baseName = fields["name"].flatMap { $0.isEmpty ? nil : $0 } ?? fallback
        let listing = "\(baseName): \(fields["description"] ?? "")"
        return InventoryItem(
            kind: kind,
            name: prefix.map { "\($0):\(baseName)" } ?? baseName,
            scope: scope,
            path: url.path,
            enabled: enabled,
            estimatedTokens: estimatedTokens(bytes: listing.utf8.count)
        )
    }

    static func frontmatter(_ text: String) -> [String: String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [:] }
        var fields: [String: String] = [:]
        var currentKey: String?
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            if let first = line.first, first == " " || first == "\t" {
                guard let key = currentKey else { continue }
                let piece = line.trimmingCharacters(in: .whitespaces)
                fields[key] = [fields[key] ?? "", piece].filter { !$0.isEmpty }.joined(separator: " ")
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { currentKey = nil; continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if [">", "|", ">-", "|-"].contains(value) { value = "" }
            fields[key] = unquoted(value)
            currentKey = key
        }
        return fields
    }

    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" else { return value }
        return String(value.dropFirst().dropLast())
    }

    private static func mcpServers(
        config: [String: Any],
        configPath: String,
        projectConfig: [String: Any],
        settings: [String: Any],
        project: URL?
    ) -> [InventoryItem] {
        let disabled = Set(strings(projectConfig["disabledMcpServers"]))
        var items = serverNames(config["mcpServers"]).map {
            InventoryItem(kind: .mcpServer, name: $0, scope: .user, path: configPath, enabled: !disabled.contains($0))
        }
        items += serverNames(projectConfig["mcpServers"]).map {
            InventoryItem(kind: .mcpServer, name: $0, scope: .project, path: configPath, enabled: !disabled.contains($0))
        }
        guard let project else { return items }
        let mcpJson = project.appendingPathComponent(".mcp.json")
        let approved = Set(strings(settings["enabledMcpjsonServers"]) + strings(projectConfig["enabledMcpjsonServers"]))
        let rejected = Set(strings(settings["disabledMcpjsonServers"]) + strings(projectConfig["disabledMcpjsonServers"]))
        let approveAll = settings["enableAllProjectMcpServers"] as? Bool == true
        items += serverNames(json(at: mcpJson)?["mcpServers"]).map { name in
            let enabled: Bool? = rejected.contains(name) ? false : (approveAll || approved.contains(name)) ? true : nil
            return InventoryItem(kind: .mcpServer, name: name, scope: .project, path: mcpJson.path, enabled: enabled)
        }
        return items
    }

    private static func plugins(claudeDir: URL, settings: [String: Any], project: URL?) -> [InventoryItem] {
        let pluginsDir = claudeDir.appendingPathComponent("plugins", isDirectory: true)
        guard let installed = json(at: pluginsDir.appendingPathComponent("installed_plugins.json"))?["plugins"] as? [String: Any] else { return [] }
        let enabledPlugins = settings["enabledPlugins"] as? [String: Any] ?? [:]
        return installed.keys.sorted().flatMap { key -> [InventoryItem] in
            let installs = installed[key] as? [[String: Any]] ?? []
            let install = installs.first { ($0["projectPath"] as? String).map { $0 == project?.path } ?? true }
            guard let installPath = install?["installPath"] as? String else { return [] }
            let root = URL(fileURLWithPath: installPath, isDirectory: true)
            let pluginName = String(key.split(separator: "@").first ?? Substring(key))
            let enabled = enabledPlugins[key] as? Bool == true
            let manifest = json(at: root.appendingPathComponent(".claude-plugin/plugin.json")) ?? [:]
            var items = [InventoryItem(kind: .plugin, name: key, scope: .plugin, path: installPath, enabled: enabled)]
            items += markdownComponents(in: root, scope: .plugin, prefix: pluginName, enabled: enabled, manifest: manifest)
            let mcpJson = root.appendingPathComponent(".mcp.json")
            let fileServers = json(at: mcpJson).map { serverNames($0["mcpServers"] ?? $0) } ?? []
            let inlineServers = serverNames(manifest["mcpServers"])
            items += (fileServers + inlineServers).map {
                InventoryItem(kind: .mcpServer, name: "\(pluginName):\($0)", scope: .plugin, path: installPath, enabled: enabled)
            }
            return items
        }
    }

    private static func mergedSettings(claudeDir: URL, project: URL?) -> [String: Any] {
        var files = [claudeDir.appendingPathComponent("settings.json")]
        if let project {
            files.append(project.appendingPathComponent(".claude/settings.json"))
            files.append(project.appendingPathComponent(".claude/settings.local.json"))
        }
        return files.compactMap { json(at: $0) }.reduce(into: [:]) { merged, settings in
            for (key, value) in settings {
                if let current = merged[key] as? [String: Any], let extra = value as? [String: Any] {
                    merged[key] = current.merging(extra) { $1 }
                } else if let current = merged[key] as? [Any], let extra = value as? [Any] {
                    merged[key] = current + extra
                } else {
                    merged[key] = value
                }
            }
        }
    }

    private static func serverNames(_ value: Any?) -> [String] {
        (value as? [String: Any])?.keys.sorted() ?? []
    }

    private static func strings(_ value: Any?) -> [String] {
        value as? [String] ?? []
    }

    private static func paths(_ value: Any?) -> [String] {
        if let single = value as? String { return [single] }
        return strings(value)
    }

    private static func children(of dir: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )) ?? []
        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func read(_ url: URL) -> Data? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func json(at url: URL) -> [String: Any]? {
        read(url).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
}
