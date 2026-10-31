import SwiftUI

struct ContentView: View {
    @Environment(SessionStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Preferences.showBackground) private var showBackground = false
    @State private var selection: String?
    @State private var search = ""
    @State private var showNewChat = false

    private var filtered: [Session] {
        let all = store.sessions
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.title.lowercased().contains(q) || $0.cwd.lowercased().contains(q)
                || ($0.meta?.lastPrompt?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        let sessions = filtered
        let liveSessions = sessions.filter(\.isLive)
        let recent = sessions.filter { !$0.isLive }

        NavigationSplitView {
            List(selection: $selection) {
                if !store.hooksInstalled {
                    HooksBanner()
                }
                if !liveSessions.isEmpty {
                    Section(String(localized: "Running")) {
                        ForEach(Array(liveSessions.enumerated()), id: \.element.id) { index, s in
                            SessionRow(session: s, shortcut: index < 9 ? index + 1 : nil)
                                .tag(s.id)
                        }
                    }
                }
                Section(String(localized: "Recent")) {
                    ForEach(recent) { s in
                        SessionRow(session: s, shortcut: nil).tag(s.id)
                    }
                }
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first, let s = store.session(id) {
                    SessionActions(session: s)
                }
            } primaryAction: { ids in
                guard let id = ids.first, let s = store.session(id) else { return }
                if s.isLive { store.focus(id) } else { store.resume(id) }
            }
            .searchable(text: $search, placement: .sidebar, prompt: Text("Search chats"))
            .navigationSplitViewColumnWidth(min: 280, ideal: 330, max: 460)
            .background(shortcutButtons(liveSessions))
        } detail: {
            if let id = selection, let s = store.session(id) {
                SessionDetail(session: s)
                    .id(id)
            } else {
                ContentUnavailableView(
                    String(localized: "Pick a chat"),
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Double-click a chat to jump to its terminal. ⌘1–⌘9 switch between running chats.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openWindow(id: "workspace")
                } label: {
                    Label(String(localized: "Workspace"), systemImage: "square.stack.3d.up")
                }
                .help(String(localized: "What every chat in a project starts with (⇧⌘I)"))
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewChat = true
                } label: {
                    Label(String(localized: "New Chat"), systemImage: "square.and.pencil")
                }
                .help(String(localized: "New chat in a folder (⌘N)"))
            }
        }
        .sheet(isPresented: $showNewChat) {
            NewChatSheet(initialDirectory: selection.flatMap { store.session($0)?.cwd })
                .environment(store)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newChatRequested)) { _ in
            showNewChat = true
        }
        .onChange(of: selection) { _, id in
            if let id { store.markSeen(id) }
        }
        .onChange(of: selectionNeedsAttention) { _, attention in
            if attention, NSApp.isActive, let id = selection { store.markSeen(id) }
        }
    }

    private var selectionNeedsAttention: Bool {
        selection.flatMap { store.session($0)?.needsAttention } ?? false
    }

    private func shortcutButtons(_ live: [Session]) -> some View {
        ZStack {
            ForEach(Array(live.prefix(9).enumerated()), id: \.element.id) { index, s in
                Button("") {
                    selection = s.id
                    store.focus(s.id)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                .opacity(0)
            }
        }
        .frame(width: 0, height: 0)
    }
}

struct HooksBanner: View {
    @Environment(SessionStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "Live status is off"), systemImage: "bolt.slash")
                .font(.headline)
            Text("ThreadHaven needs a small Claude Code hook to know when a chat is working, waiting for approval or done. Your existing hooks are kept and settings.json is backed up first.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(String(localized: "Install hook")) { store.installHooks() }
                .buttonStyle(.borderedProminent)
            if let err = store.lastError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .listRowSeparator(.hidden)
    }
}

struct SessionActions: View {
    @Environment(SessionStore.self) private var store
    let session: Session

    var body: some View {
        if session.isLive {
            Button(String(localized: "Go to Terminal")) { store.focus(session.id) }
            Button(String(localized: "Compact Now")) { store.compact(session.id) }
                .disabled(!TerminalBridge.canSend(to: session))
        } else {
            Button(String(localized: "Resume in Terminal")) { store.resume(session.id) }
        }
        Button(String(localized: "Hand Off to a Fresh Chat")) { store.handOff(session.id) }
            .disabled(session.cwd.isEmpty || session.agent != .claude)
        Button(String(localized: "New Chat Here (continue)")) {
            store.newChat(in: session.cwd, continueLast: true, prompt: "")
        }
        .disabled(session.cwd.isEmpty)
        Divider()
        Button(String(localized: "Show in Finder")) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: session.cwd)
        }
        Button(String(localized: "Copy Session ID")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(session.id, forType: .string)
        }
    }
}
