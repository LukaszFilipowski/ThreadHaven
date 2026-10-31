import SwiftUI

struct MenuBarView: View {
    @Environment(SessionStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Preferences.showBackground) private var showBackground = false

    var body: some View {
        let running = store.sessions.filter(\.isLive)
        VStack(alignment: .leading, spacing: 0) {
            Text("Running chats")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)
            if running.isEmpty {
                Text(store.hooksInstalled ? String(localized: "No running chats") : String(localized: "Install the hook in ThreadHaven to see live chats"))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(running) { s in
                            Button {
                                store.focus(s.id)
                            } label: {
                                SessionRow(session: s, shortcut: nil)
                                    .padding(.horizontal, 8)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(MenuRowStyle())
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxHeight: 420)
            }
            Divider()
            HStack {
                Button(String(localized: "Open ThreadHaven")) {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button(String(localized: "Quit")) { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
        .frame(width: 340)
    }
}

struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.accentColor.opacity(0.2) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6))
    }
}
