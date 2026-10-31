import SwiftUI

@main
struct ThreadHavenApp: App {
    @State private var store = SessionStore()
    @AppStorage(Preferences.showBackground) private var showBackground = false

    var body: some Scene {
        Window("ThreadHaven", id: "main") {
            ContentView()
                .environment(store)
                .frame(minWidth: 820, minHeight: 520)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(String(localized: "New Chat…")) {
                    NotificationCenter.default.post(name: .newChatRequested, object: nil)
                }
                .keyboardShortcut("n")
            }
        }

        Window("Workspace", id: "workspace") {
            WorkspaceView()
                .environment(store)
                .frame(minWidth: 620, minHeight: 440)
        }
        .defaultSize(width: 760, height: 640)
        .keyboardShortcut("w", modifiers: [.command, .shift])

        MenuBarExtra {
            MenuBarView()
                .environment(store)
        } label: {
            MenuBarLabel(count: store.attentionCount, working: store.sessions.contains { $0.status == .working })
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}

extension Notification.Name {
    static let newChatRequested = Notification.Name("ThreadHavenNewChatRequested")
}

struct MenuBarLabel: View {
    let count: Int
    let working: Bool

    var body: some View {
        if count > 0 {
            Label("\(count)", systemImage: "bubble.left.and.exclamationmark.bubble.right.fill")
                .labelStyle(.titleAndIcon)
        } else {
            Image(systemName: working ? "bubble.left.and.text.bubble.right.fill" : "bubble.left.and.bubble.right")
        }
    }
}
