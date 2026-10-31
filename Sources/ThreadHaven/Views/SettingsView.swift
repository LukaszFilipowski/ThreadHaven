import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(SessionStore.self) private var store
    @AppStorage(Preferences.terminalKey) private var terminal = TerminalApp.terminal.rawValue
    @AppStorage(Preferences.daysBack) private var daysBack = 14
    @AppStorage(Preferences.showBackground) private var showBackground = false
    @AppStorage(Preferences.notify) private var notify = true
    @AppStorage(Preferences.autoCompact) private var autoCompact = false
    @AppStorage(Preferences.compactTokens) private var compactTokens = 150_000
    @AppStorage(Preferences.handoffModel) private var handoffModel = "haiku"
    @AppStorage(Preferences.polishModel) private var polishModel = "haiku"
    @AppStorage("dictationLocale") private var dictationLocale = Locale.current.identifier
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section(String(localized: "General")) {
                Picker(String(localized: "Terminal for new chats"), selection: $terminal) {
                    ForEach(TerminalApp.allCases) { Text($0.name).tag($0.rawValue) }
                }
                Stepper(value: $daysBack, in: 1...90) {
                    Text("Show chats from the last \(daysBack) days")
                }
                Toggle(String(localized: "Show background sessions (claude -p, SDK)"), isOn: $showBackground)
                Toggle(String(localized: "Launch at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            Section(String(localized: "Notifications")) {
                Toggle(String(localized: "Notify when a chat finishes or needs approval"), isOn: $notify)
                LabeledContent(String(localized: "Claude Code hook")) {
                    if store.hooksInstalled {
                        HStack {
                            Label(String(localized: "Installed"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Button(String(localized: "Remove")) { store.uninstallHooks() }
                        }
                    } else {
                        Button(String(localized: "Install")) { store.installHooks() }
                    }
                }
                if let err = store.lastError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                Toggle(String(localized: "Auto-compact long chats"), isOn: $autoCompact)
                HStack {
                    Slider(value: compactTokensValue, in: 50_000...500_000, step: 25_000) {
                        Text("Threshold")
                    }
                    Text(ContextGauge.short(compactTokens)).monospacedDigit().frame(width: 52, alignment: .trailing)
                }
                .disabled(!autoCompact)
                Picker(String(localized: "Model for handoff notes"), selection: $handoffModel) {
                    Text("Haiku").tag("haiku")
                    Text("Sonnet").tag("sonnet")
                    Text("Opus").tag("opus")
                }
            } header: {
                Text("Context")
            } footer: {
                Text("Every turn re-reads the whole context, so smaller chats go further on the same plan. When a running chat finishes a turn above the threshold, ThreadHaven sends /compact to it (Terminal and iTerm2 only).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(String(localized: "Dictation & prompt polishing")) {
                Picker(String(localized: "Dictation language"), selection: $dictationLocale) {
                    Text("Polski").tag("pl_PL")
                    Text("English (US)").tag("en_US")
                    Text("English (UK)").tag("en_GB")
                    Text("Deutsch").tag("de_DE")
                    if !["pl_PL", "en_US", "en_GB", "de_DE"].contains(dictationLocale) {
                        Text(dictationLocale).tag(dictationLocale)
                    }
                }
                Picker(String(localized: "Model for polishing"), selection: $polishModel) {
                    Text("Haiku").tag("haiku")
                    Text("Sonnet").tag("sonnet")
                    Text("Opus").tag("opus")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding(.vertical, 8)
    }

    private var compactTokensValue: Binding<Double> {
        Binding(get: { Double(compactTokens) }, set: { compactTokens = Int($0) })
    }
}
