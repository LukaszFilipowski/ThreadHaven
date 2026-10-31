import Foundation

enum Preferences {
    static let terminalKey = "terminal"
    static let daysBack = "daysBack"
    static let showBackground = "showBackground"
    static let notify = "notify"
    static let autoCompact = "autoCompact"
    static let compactThreshold = "compactThreshold"
    static let polishModel = "polishModel"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            terminalKey: TerminalApp.terminal.rawValue,
            daysBack: 14,
            showBackground: false,
            notify: true,
            autoCompact: false,
            compactThreshold: 70.0,
            polishModel: "haiku",
        ])
    }

    static var terminal: TerminalApp {
        TerminalApp(rawValue: UserDefaults.standard.string(forKey: terminalKey) ?? "") ?? .terminal
    }
}
