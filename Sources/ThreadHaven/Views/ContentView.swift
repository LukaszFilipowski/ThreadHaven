import SwiftUI

struct ContentView: View {
    @Environment(SessionStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Preferences.showBackground) private var showBackground = false
    @State private var selection: String?
    @AppStorage(Preferences.privateMode) private var privateMode = false

    init(selection: String? = nil) {
        _selection = State(initialValue: selection)
    }
    @State private var search = ""
    @State private var showNewChat = false

    private var filtered: [Session] {
        let all = store.sessions
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.title.lowercased().contains(q) || $0.cwd.lowercased().contains(q)
                || ($0.meta?.lastPrompt?.lowercased().contains(q) ?? false)
                || ($0.meta?.gitBranch?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        let sessions = filtered
        let liveSessions = SidebarLayout(sessions: sessions).running

        NavigationSplitView {
            ChatSidebar(selection: $selection, sessions: privateMode ? sessions.filter(\.isLive) : sessions, pending: store.terminals.pending)
                .searchable(text: $search, placement: .sidebar, prompt: Text("Search chats"))
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 480)
                .background(shortcutButtons(liveSessions))
        } detail: {
            if let id = selection, let s = store.session(id) {
                SessionDetail(session: s)
                    .id(id)
            } else if let id = selection, let pending = store.terminals.pending.first(where: { $0.id == id }) {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill").foregroundStyle(Color.accentColor)
                        Text(pending.project).font(.headline)
                        Text(pending.linkedSession.flatMap { store.session($0)?.title } ?? String(localized: "New chat"))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        CloseChatButton { store.requestClose(id) }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    Divider()
                    TerminalPane(id: id, session: nil)
                }
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
            ToolbarItem(placement: .navigation) {
                Toggle(isOn: $privateMode) {
                    Label(String(localized: "Private Mode"), systemImage: privateMode ? "eye.slash.fill" : "eye.slash")
                }
                .help(String(localized: "Private mode shows only running chats"))
            }
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
            store.selectedID = id
            if let id { store.markSeen(id) }
        }
        .confirmationDialog(
            closeTitle,
            isPresented: Binding(get: { store.closeRequest != nil }, set: { if !$0 { store.closeRequest = nil } }),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Close Chat"), role: .destructive) {
                if let id = store.closeRequest { store.close(id) }
                store.closeRequest = nil
            }
        } message: {
            Text("This stops Claude or Codex in this chat and everything it started, such as running commands and MCP servers. The conversation stays in the list and can be resumed.")
        }
        .onChange(of: store.selectionRequest) { _, request in
            guard let request else { return }
            selection = request
            store.selectionRequest = nil
        }
        .onChange(of: sessions.isEmpty, initial: true) { _, empty in
            if selection == nil, !empty { selection = SidebarLayout(sessions: sessions).ordered.first?.id }
        }
        .onChange(of: selectionNeedsAttention) { _, attention in
            if attention, NSApp.isActive, let id = selection { store.markSeen(id) }
        }
    }

    private var closeTitle: String {
        let title = store.closeRequest.flatMap { store.session($0)?.title } ?? String(localized: "this chat")
        return String(localized: "Close “\(title)”?")
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
    }
}

struct SessionActions: View {
    @Environment(SessionStore.self) private var store
    let session: Session

    var body: some View {
        Button(store.isFavorite(session.id) ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites")) {
            store.toggleFavorite(session.id)
        }
        Divider()
        if session.isLive {
            Button(String(localized: "Go to Terminal")) { store.focus(session.id) }
            Button(String(localized: "Compact Now")) { store.compact(session.id) }
                .disabled(!TerminalBridge.canCompact(session))
        } else {
            Button(String(localized: "Resume in Terminal")) { store.resume(session.id) }
        }
        Button(String(localized: "Hand Off to a Fresh Chat")) { store.handOff(session.id) }
            .disabled(session.cwd.isEmpty || session.agent != .claude)
        Button(String(localized: "New Chat Here (continue)")) {
            store.newChat(in: session.cwd, continueLast: true, prompt: "")
        }
        .disabled(session.cwd.isEmpty)
        if session.isLive || store.terminals.isRunning(session.id) {
            Divider()
            Button(String(localized: "Close Chat…"), role: .destructive) { store.requestClose(session.id) }
        }
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
