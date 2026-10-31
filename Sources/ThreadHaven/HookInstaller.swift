import Foundation

enum HookInstaller {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let supportDir = home.appendingPathComponent(".threadhaven", isDirectory: true)
    static let hookURL = supportDir.appendingPathComponent("hook.sh")
    static let eventsURL = supportDir.appendingPathComponent("events.jsonl")
    static let settingsURL = home.appendingPathComponent(".claude/settings.json")
    static let hookEvents = ["SessionStart", "UserPromptSubmit", "PostToolUse", "Notification", "Stop", "SessionEnd"]
    static let marker = ".threadhaven/hook.sh"

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
    s=$(stat -f%z "$f" 2>/dev/null || echo 0)
    [ "$s" -gt 5000000 ] && mv -f "$f" "$f.1"
    t=$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')
    printf '{"ts":%s,"term":"%s","bundle":"%s","tty":"%s","event":%s}\n' "$(date +%s)" "${TERM_PROGRAM:-}" "${__CFBundleIdentifier:-}" "$t" "$p" >> "$f"
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
        guard let settings = try? loadSettings(), let hooks = settings["hooks"] as? [String: Any] else { return false }
        return hookEvents.allSatisfy { event in
            (hooks[event] as? [[String: Any]] ?? []).contains(where: containsOurHook)
        }
    }

    static func install() throws {
        try writeScript()
        var settings = try loadSettings()
        try backup()
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in hookEvents {
            var groups = (hooks[event] as? [[String: Any]] ?? []).filter { !containsOurHook($0) }
            groups.append(["hooks": [["type": "command", "command": hookURL.path, "timeout": 5]]])
            hooks[event] = groups
        }
        settings["hooks"] = hooks
        try save(settings)
    }

    static func uninstall() throws {
        var settings = try loadSettings()
        guard var hooks = settings["hooks"] as? [String: Any] else { return }
        try backup()
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept = groups.filter { !containsOurHook($0) }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        try save(settings)
    }

    private static func containsOurHook(_ group: [String: Any]) -> Bool {
        (group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String)?.contains(marker) == true }
    }

    private static func loadSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        if data.isEmpty { return [:] }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return obj
    }

    private static func backup() throws {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return }
        let dst = settingsURL.deletingLastPathComponent().appendingPathComponent("settings.json.threadhaven-backup")
        try? FileManager.default.removeItem(at: dst)
        try FileManager.default.copyItem(at: settingsURL, to: dst)
    }

    private static func save(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: settingsURL, options: .atomic)
    }
}
