import Foundation

enum Preferences {
    static let terminalKey = "terminal"
    static let daysBack = "daysBack"
    static let showBackground = "showBackground"
    static let notify = "notify"
    static let autoCompact = "autoCompact"
    static let compactTokens = "compactTokens"
    static let handoffModel = "handoffModel"
    static let polishModel = "polishModel"
    static let quickSwitcher = "quickSwitcher"
    static let openInApp = "openInApp"
    static let favorites = "favorites"
    static let expandedSections = "expandedSections"
    static let remoteEnabled = "remoteEnabled"
    static let remotePort = "remotePort"
    static let remoteIdleHours = "remoteIdleHours"
    static let remotePreviews = "remotePreviews"
    static let remoteAllowlist = "remoteAllowlist"
    static let remoteDeviceCounter = "remoteDeviceCounter"
    static let remotePushContact = "remotePushContact"
    static let remoteSignOutOnQuit = "remoteSignOutOnQuit"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            terminalKey: TerminalApp.terminal.rawValue,
            daysBack: 90,
            showBackground: false,
            notify: true,
            autoCompact: false,
            compactTokens: 150_000,
            handoffModel: "haiku",
            polishModel: "haiku",
            quickSwitcher: true,
            openInApp: true,
            remoteEnabled: false,
            remoteIdleHours: 8,
            remotePreviews: false,
            remoteAllowlist: "",
            remoteSignOutOnQuit: false,
        ])
    }

    static var terminal: TerminalApp {
        TerminalApp(rawValue: UserDefaults.standard.string(forKey: terminalKey) ?? "") ?? .terminal
    }
}
