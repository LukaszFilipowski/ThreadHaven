import Foundation

enum HookInstaller {
    enum Failure: LocalizedError {
        case unexpectedFormat(String)

        var errorDescription: String? {
            switch self {
            case .unexpectedFormat(let key):
                String(localized: "Unexpected format of \(key) in ~/.claude/settings.json. Nothing was changed.")
            }
        }
    }

    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let supportDir = home.appendingPathComponent(".threadhaven", isDirectory: true)
    static let hookURL = supportDir.appendingPathComponent("hook.sh")
    static let eventsURL = supportDir.appendingPathComponent("events.jsonl")
    static let settingsURL = home.appendingPathComponent(".claude/settings.json")
    static let hookEvents = ["SessionStart", "UserPromptSubmit", "PostToolUse", "Notification", "Stop", "SessionEnd"]
    static let marker = ".threadhaven/hook.sh"
    static var command: String { "\"\(hookURL.path)\"" }

    static let script = #"""
    #!/bin/sh
    d="$HOME/.threadhaven"
    f="$d/events.jsonl"
    p=$(cat | tr -d '\n')
    [ -z "$p" ] && exit 0
    mkdir -p "$d"
    case "$p" in
      *'"hook_event_name":"PostToolUse"'*|*'"hook_event_name": "PostToolUse"'*)
        sid=$(printf '%s' "$p" | head -c 600 | sed -n 's/.*"session_id" *: *"\([^"]*\)".*/\1/p')
        p="{\"session_id\":\"$sid\",\"hook_event_name\":\"PostToolUse\"}"
        ;;
    esac
    t=$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')
    printf '{"ts":%s,"term":"%s","bundle":"%s","tty":"%s","event":%s}\n' "$(date +%s)" "${TERM_PROGRAM:-}" "${__CFBundleIdentifier:-}" "$t" "$p" |
      /usr/bin/lockf -k -t 2 "$d/.lock" /bin/sh -c '
        s=$(stat -f%z "$1" 2>/dev/null || echo 0)
        [ "$s" -gt 5000000 ] && mv -f "$1" "$1.1"
        cat >> "$1"
      ' sh "$f"
    exit 0
    """#

    static func writeScript() throws {
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let current = try? String(contentsOf: hookURL, encoding: .utf8)
        if current != script {
            try script.write(to: hookURL, atomically: true, encoding: .utf8)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookURL.path)
        if !FileManager.default.fileExists(atPath: eventsURL.path) {
            FileManager.default.createFile(atPath: eventsURL.path, contents: nil)
        }
    }

    static var isInstalled: Bool {
        guard let settings = try? loadSettings() else { return false }
        return isInstalled(in: settings)
    }

    static func install() throws {
        try writeScript()
        let settings = try loadSettings()
        try save(installing(into: settings, command: command))
    }

    static func uninstall() throws {
        let settings = try loadSettings()
        try save(removing(from: settings))
    }

    static func isInstalled(in settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return hookEvents.allSatisfy { event in
            (hooks[event] as? [[String: Any]] ?? []).contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains(where: isOurs)
            }
        }
    }

    static func installing(into settings: [String: Any], command: String) throws -> [String: Any] {
        var settings = try removing(from: settings)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in hookEvents {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups.append(["hooks": [["type": "command", "command": command, "timeout": 5]]])
            hooks[event] = groups
        }
        settings["hooks"] = hooks
        return settings
    }

    static func removing(from settings: [String: Any]) throws -> [String: Any] {
        guard let value = settings["hooks"] else { return settings }
        guard var hooks = value as? [String: Any] else { throw Failure.unexpectedFormat("hooks") }
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { throw Failure.unexpectedFormat("hooks.\(event)") }
            let kept = withoutOurHook(groups)
            hooks[event] = kept.isEmpty ? nil : kept
        }
        var settings = settings
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        return settings
    }

    private static func withoutOurHook(_ groups: [[String: Any]]) -> [[String: Any]] {
        groups.compactMap { group in
            guard let entries = group["hooks"] as? [[String: Any]] else { return group }
            let kept = entries.filter { !isOurs($0) }
            if kept.count == entries.count { return group }
            if kept.isEmpty { return nil }
            var group = group
            group["hooks"] = kept
            return group
        }
    }

    private static func isOurs(_ entry: [String: Any]) -> Bool {
        (entry["command"] as? String)?.contains(marker) == true
    }

    private static func loadSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        if data.isEmpty { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.unexpectedFormat("settings")
        }
        return object
    }

    private static func save(_ settings: [String: Any]) throws {
        let fm = FileManager.default
        let target = settingsURL.resolvingSymlinksInPath()
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

        let backup = target.deletingLastPathComponent().appendingPathComponent("settings.json.threadhaven-backup")
        if fm.fileExists(atPath: target.path) && !fm.fileExists(atPath: backup.path) {
            try fm.copyItem(at: target, to: backup)
        }

        let permissions = (try? fm.attributesOfItem(atPath: target.path))?[.posixPermissions]
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: target, options: .atomic)
        if let permissions {
            try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
        }
    }
}
