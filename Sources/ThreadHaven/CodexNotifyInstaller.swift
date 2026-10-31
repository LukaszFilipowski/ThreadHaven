import Foundation

enum CodexNotifyInstaller {
    enum State: Equatable {
        case unavailable
        case absent
        case ours
        case foreign
        case unsupported
    }

    enum Failure: LocalizedError, Equatable {
        case unexpectedFormat(String)
        case inUse

        var errorDescription: String? {
            switch self {
            case .unexpectedFormat(let reason):
                String(localized: "Unexpected content in ~/.codex/config.toml (\(reason)). Nothing was changed.")
            case .inUse:
                String(localized: "notify in ~/.codex/config.toml is already used by another program. Nothing was changed.")
            }
        }
    }

    static let codexDir = HookInstaller.home.appendingPathComponent(".codex", isDirectory: true)
    static let configURL = codexDir.appendingPathComponent("config.toml")
    static let scriptURL = HookInstaller.supportDir.appendingPathComponent("codex-notify.sh")
    static let marker = ".threadhaven/codex-notify.sh"

    static let script = #"""
    #!/bin/sh
    umask 077
    d="$HOME/.threadhaven"
    f="$d/events.jsonl"
    p=$(printf '%s' "${1:-}" | tr -d '\n')
    case "$p" in
      *'"type":"agent-turn-complete"'*) ;;
      *) exit 0 ;;
    esac
    field() {
      printf '%s' "$p" | sed -n -E 's/.*"'"$1"'":"(([^"\\]|\\.)*)".*/\1/p'
    }
    clean() {
      printf '%s' "$1" | tr -cd 'A-Za-z0-9._-'
    }
    id=$(clean "$(field thread-id)")
    [ -z "$id" ] && exit 0
    mkdir -p "$d"
    e="{\"session_id\":\"$id\",\"hook_event_name\":\"CodexTurnComplete\",\"cwd\":\"$(field cwd)\",\"last_assistant_message\":\"$(field last-assistant-message)\"}"
    t=$(clean "$(ps -o tty= -p $PPID 2>/dev/null)")
    printf '{"ts":%s,"term":"%s","bundle":"%s","tty":"%s","event":%s}\n' "$(date +%s)" "$(clean "${TERM_PROGRAM:-}")" "$(clean "${__CFBundleIdentifier:-}")" "$t" "$e" |
      /usr/bin/lockf -k -t 2 "$d/.lock" /bin/sh -c '
        s=$(stat -f%z "$1" 2>/dev/null || echo 0)
        [ "$s" -gt 5000000 ] && mv -f "$1" "$1.1"
        cat >> "$1"
      ' sh "$f"
    exit 0
    """#

    static func notifyLine(scriptPath: String) -> String {
        let escaped = scriptPath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "notify = [\"\(escaped)\"]"
    }

    static var state: State {
        guard FileManager.default.fileExists(atPath: codexDir.path) else { return .unavailable }
        do {
            guard let content = try load(configURL) else { return .absent }
            return try state(of: content)
        } catch {
            return .unsupported
        }
    }

    static func install() throws {
        try HookInstaller.writeScript()
        try install(config: configURL, scriptPath: scriptURL.path)
    }

    static func uninstall() throws {
        try uninstall(config: configURL)
    }

    static func install(config: URL, scriptPath: String) throws {
        let content = try load(config) ?? ""
        try save(installing(into: content, line: notifyLine(scriptPath: scriptPath)), to: config)
    }

    static func uninstall(config: URL) throws {
        guard let content = try load(config) else { return }
        try save(removing(from: content), to: config)
    }

    static func state(of content: String) throws -> State {
        let found = try notifyLines(in: content)
        guard let index = found.first else { return .absent }
        let lines = content.components(separatedBy: "\n")
        return found.count == 1 && isOurs(lines[index]) ? .ours : .foreign
    }

    static func installing(into content: String, line: String) throws -> String {
        switch try state(of: content) {
        case .ours: return content
        case .foreign: throw Failure.inUse
        default: return line + "\n" + content
        }
    }

    static func removing(from content: String) throws -> String {
        let found = try notifyLines(in: content)
        guard let index = found.first else { return content }
        var lines = content.components(separatedBy: "\n")
        guard found.count == 1, isOurs(lines[index]) else { throw Failure.inUse }
        lines.remove(at: index)
        return lines.joined(separator: "\n")
    }

    private static func notifyLines(in content: String) throws -> [Int] {
        if content.utf8.contains(13) { throw Failure.unexpectedFormat("CRLF") }
        if content.hasPrefix("\u{FEFF}") { throw Failure.unexpectedFormat("BOM") }
        var result: [Int] = []
        for (index, line) in content.components(separatedBy: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { break }
            if trimmed.contains("\"\"\"") || trimmed.contains("'''") { throw Failure.unexpectedFormat("multi-line string") }
            if isNotifyKey(trimmed) { result.append(index) }
        }
        return result
    }

    private static func isNotifyKey(_ line: String) -> Bool {
        for key in ["notify", "\"notify\"", "'notify'"] where line.hasPrefix(key) {
            let rest = line.dropFirst(key.count).drop { $0 == " " || $0 == "\t" }
            if rest.hasPrefix("=") { return true }
        }
        return false
    }

    private static func isOurs(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("notify = [\"") && trimmed.hasSuffix("\"]")
            && trimmed.contains(marker) && !trimmed.contains(",")
    }

    private static func load(_ config: URL) throws -> String? {
        let target = config.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: target.path) else { return nil }
        let data = try Data(contentsOf: target)
        guard !data.starts(with: [0xEF, 0xBB, 0xBF]) else { throw Failure.unexpectedFormat("BOM") }
        guard let content = String(data: data, encoding: .utf8), Data(content.utf8) == data else {
            throw Failure.unexpectedFormat("encoding")
        }
        return content
    }

    private static func save(_ content: String, to config: URL) throws {
        let fm = FileManager.default
        let target = config.resolvingSymlinksInPath()
        let exists = fm.fileExists(atPath: target.path)
        if exists {
            guard (try fm.attributesOfItem(atPath: target.path))[.type] as? FileAttributeType == .typeRegular else {
                throw Failure.unexpectedFormat("not a file")
            }
            let backup = target.deletingLastPathComponent().appendingPathComponent("config.toml.threadhaven-backup")
            if !fm.fileExists(atPath: backup.path) { try fm.copyItem(at: target, to: backup) }
        }
        let permissions = exists ? (try fm.attributesOfItem(atPath: target.path))[.posixPermissions] : NSNumber(value: 0o600)
        try Data(content.utf8).write(to: target, options: .atomic)
        if let permissions {
            try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
        }
    }
}
