import SwiftUI

@main
struct ThreadHavenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: SessionStore
    @State private var remote: RemoteAccess
    @AppStorage(Preferences.showBackground) private var showBackground = false
    private let switcher: QuickSwitcher

    init() {
        let store = SessionStore()
        _store = State(initialValue: store)
        _remote = State(initialValue: RemoteAccess(store: store))
        switcher = QuickSwitcher(store: store)
    }

    var body: some Scene {
        Window("ThreadHaven", id: "main") {
            ContentView()
                .environment(store)
                .frame(minWidth: 820, minHeight: 520)
        }
        .defaultSize(width: 1100, height: 720)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
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
        .keyboardShortcut("i", modifiers: [.command, .shift])

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
                .environment(remote)
        }
    }
}

extension Notification.Name {
    static let newChatRequested = Notification.Name("ThreadHavenNewChatRequested")
    static let mainWindowRequested = Notification.Name("ThreadHavenMainWindowRequested")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if !Self.mainWindowVisible { NotificationCenter.default.post(name: .mainWindowRequested, object: nil) }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !Self.mainWindowVisible { NotificationCenter.default.post(name: .mainWindowRequested, object: nil) }
        return true
    }

    static var mainWindowVisible: Bool {
        NSApp.windows.contains { $0.isVisible && $0.identifier?.rawValue.hasPrefix("main") == true }
    }
}

struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    let count: Int
    let working: Bool

    var body: some View {
        Group {
            if count > 0 {
                Label("\(count)", systemImage: "bubble.left.and.exclamationmark.bubble.right.fill")
                    .labelStyle(.titleAndIcon)
            } else {
                Image(systemName: working ? "bubble.left.and.text.bubble.right.fill" : "bubble.left.and.bubble.right")
            }
        }
        .onChange(of: count, initial: true) { _, count in
            NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .mainWindowRequested)) { _ in
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
