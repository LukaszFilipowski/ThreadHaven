import Foundation
import Testing
@testable import ThreadHaven

struct HookInstallerTests {
    private let ours = "\"/Users/x/.threadhaven/hook.sh\""

    private func commands(_ settings: [String: Any], _ event: String) -> [String] {
        let groups = (settings["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
        return groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
    }

    @Test func installKeepsExistingHooksAndOtherSettings() throws {
        let settings: [String: Any] = [
            "model": "opus",
            "hooks": ["UserPromptSubmit": [["hooks": [["type": "command", "command": "echo prompt-received"]]]]],
        ]
        let installed = try HookInstaller.installing(into: settings, command: ours)
        #expect(installed["model"] as? String == "opus")
        #expect(commands(installed, "UserPromptSubmit") == ["echo prompt-received", ours])
        #expect(HookInstaller.isInstalled(in: installed))
    }

    @Test func installTwiceDoesNotDuplicate() throws {
        let once = try HookInstaller.installing(into: [:], command: ours)
        let twice = try HookInstaller.installing(into: once, command: ours)
        #expect(commands(twice, "Stop") == [ours])
    }

    @Test func uninstallRemovesOnlyOurEntryFromSharedGroup() throws {
        let settings: [String: Any] = [
            "hooks": ["Stop": [["matcher": "", "hooks": [
                ["type": "command", "command": "say done"],
                ["type": "command", "command": ours],
            ]]]],
        ]
        let removed = try HookInstaller.removing(from: settings)
        #expect(commands(removed, "Stop") == ["say done"])
        #expect(!HookInstaller.isInstalled(in: removed))
    }

    @Test func uninstallDropsEmptyHooksSection() throws {
        let installed = try HookInstaller.installing(into: ["model": "opus"], command: ours)
        let removed = try HookInstaller.removing(from: installed)
        #expect(removed["hooks"] == nil)
        #expect(removed["model"] as? String == "opus")
    }

    @Test func refusesUnexpectedFormat() {
        #expect(throws: HookInstaller.Failure.self) {
            try HookInstaller.installing(into: ["hooks": ["Stop": "oops"]], command: ours)
        }
        #expect(throws: HookInstaller.Failure.self) {
            try HookInstaller.removing(from: ["hooks": [1, 2]])
        }
    }
}
