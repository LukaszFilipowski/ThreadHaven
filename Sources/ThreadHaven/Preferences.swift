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

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            terminalKey: TerminalApp.terminal.rawValue,
            daysBack: 14,
            showBackground: false,
            notify: true,
            autoCompact: false,
            compactTokens: 150_000,
            handoffModel: "haiku",
            polishModel: "haiku",
            quickSwitcher: true,
        ])
    }

    static var terminal: TerminalApp {
        TerminalApp(rawValue: UserDefaults.standard.string(forKey: terminalKey) ?? "") ?? .terminal
    }
}
