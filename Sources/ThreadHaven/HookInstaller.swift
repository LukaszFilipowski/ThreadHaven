import Foundation

enum HookInstaller {
    enum Failure: LocalizedError {
        case unexpectedFormat(String)
        case untrustedFolder(String)

        var errorDescription: String? {
            switch self {
            case .unexpectedFormat(let key):
                String(localized: "Unexpected format of \(key) in ~/.claude/settings.json. Nothing was changed.")
            case .untrustedFolder(let path):
                String(localized: "\(path) is not a folder owned by you, so ThreadHaven will not use it.")
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
    umask 077
    d="$HOME/.threadhaven"
    f="$d/events.jsonl"
    p=$(cat | tr -d '\n')
    [ -z "$p" ] && exit 0
    mkdir -p "$d"
    field() {
      printf '%s' "$p" | head -c 4000 | sed -n "s/.*\"$1\" *: *\"\([^\"]*\)\".*/\1/p"
    }
    clean() {
      printf '%s' "$1" | tr -cd 'A-Za-z0-9._-'
    }
    case "$p" in
      *'"hook_event_name":"PostToolUse"'*|*'"hook_event_name": "PostToolUse"'*)
        p="{\"session_id\":\"$(field session_id)\",\"hook_event_name\":\"PostToolUse\"}"
        ;;
      *'"hook_event_name":"UserPromptSubmit"'*|*'"hook_event_name": "UserPromptSubmit"'*)
        p="{\"session_id\":\"$(field session_id)\",\"hook_event_name\":\"UserPromptSubmit\",\"cwd\":\"$(field cwd)\",\"transcript_path\":\"$(field transcript_path)\"}"
        ;;
    esac
    t=$(clean "$(ps -o tty= -p $PPID 2>/dev/null)")
    printf '{"ts":%s,"term":"%s","bundle":"%s","tty":"%s","event":%s}\n' "$(date +%s)" "$(clean "${TERM_PROGRAM:-}")" "$(clean "${__CFBundleIdentifier:-}")" "$t" "$p" |
      /usr/bin/lockf -k -t 2 "$d/.lock" /bin/sh -c '
        s=$(stat -f%z "$1" 2>/dev/null || echo 0)
        [ "$s" -gt 5000000 ] && mv -f "$1" "$1.1"
        cat >> "$1"
      ' sh "$f"
    exit 0
    """#

    static func writeScript() throws {
        let fm = FileManager.default
        try secureDirectory(supportDir)
        try writeExecutable(script, to: hookURL)
        try writeExecutable(CodexNotifyInstaller.script, to: CodexNotifyInstaller.scriptURL)
        if !fm.fileExists(atPath: eventsURL.path) {
            fm.createFile(atPath: eventsURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        for file in [eventsURL, eventsURL.appendingPathExtension("1")] where fm.fileExists(atPath: file.path) {
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }

    private static func writeExecutable(_ content: String, to url: URL) throws {
        if (try? String(contentsOf: url, encoding: .utf8)) != content {
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    static func secureDirectory(_ url: URL) throws {
        let fm = FileManager.default
        if let attributes = try? fm.attributesOfItem(atPath: url.path) {
            guard attributes[.type] as? FileAttributeType == .typeDirectory,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
                throw Failure.untrustedFolder(url.path)
            }
        } else {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
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
