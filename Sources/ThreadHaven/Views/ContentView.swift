import SwiftUI

struct ContentView: View {
    @Environment(SessionStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Preferences.showBackground) private var showBackground = false
    @AppStorage(Preferences.privateMode) private var privateMode = false
    @AppStorage(Preferences.recentLimit) private var recentLimit = 30
    @State private var search = ""
    @State private var paneOrder: [String] = []
    @State private var renameText = ""
    @State private var showNewChat = false

    private var filtered: [Session] {
        let all = store.sessions
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { $0.id.lowercased().hasPrefix(q.lowercased()) || $0.matches(q) }
    }

    private var selection: Set<String> { store.selection }

    private var primary: String? {
        selection.count == 1 ? selection.first : nil
    }

    var body: some View {
        @Bindable var store = store
        let sessions = filtered
        let liveSessions = SidebarLayout(sessions: sessions).running
        let searching = !search.trimmingCharacters(in: .whitespaces).isEmpty

        NavigationSplitView {
            ChatSidebar(selection: $store.selection, sessions: privateMode ? sessions.filter(\.isLive) : sessions,
                        pending: store.terminals.pending, limit: searching ? nil : recentLimit)
                .searchable(text: $search, placement: .sidebar, prompt: Text("Search chats"))
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 480)
                .background(shortcutButtons(liveSessions))
        } detail: {
            if selection.count > 1 {
                PaneGrid(ids: paneOrder.filter(selection.contains).prefix(SessionStore.maxPanes).map { $0 })
            } else if let id = primary, let s = store.session(id) {
                SessionDetail(session: s)
                    .id(id)
            } else if let id = primary, store.terminals.pending.contains(where: { $0.id == id }) {
                CompactPane(id: id, single: true)
                    .id(id)
            } else {
                ContentUnavailableView(
                    String(localized: "Pick a chat"),
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Double-click a chat to jump to its terminal. ⌘-click up to six chats to see them side by side. ⌘1–⌘9 switch between running chats.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                let available = Set(runningPaneIDs).union(selection).count
                Menu {
                    ForEach(1...SessionStore.maxPanes, id: \.self) { count in
                        Toggle(isOn: Binding(get: { selection.count == count }, set: { _ in showPanes(count) })) {
                            Text(count == 1 ? String(localized: "One chat") : String(localized: "\(count) chats side by side"))
                        }
                        .disabled(count > 1 && count > available)
                    }
                } label: {
                    Label(String(localized: "Layout"), systemImage: layoutSymbol)
                }
                .help(String(localized: "How many running chats to show side by side. Drag the borders between them to resize."))
            }
            ToolbarItem(placement: .primaryAction) {
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
            NewChatSheet(initialDirectory: primary.flatMap { store.session($0)?.cwd })
                .environment(store)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newChatRequested)) { _ in
            showNewChat = true
        }
        .onChange(of: selection, initial: true) { _, ids in
            ids.forEach(store.markSeen)
            paneOrder = PaneGrid.order(paneOrder, selection: ids, pending: store.terminals.pending.map(\.id))
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
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(get: { store.deleteRequest != nil }, set: { if !$0 { store.deleteRequest = nil } }),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Move to Trash"), role: .destructive) {
                if let id = store.deleteRequest {
                    store.selection.remove(id)
                    store.delete(id)
                }
                store.deleteRequest = nil
            }
        } message: {
            Text("The conversation is moved to the Trash and disappears from ThreadHaven. You can put it back from the Trash.")
        }
        .confirmationDialog(
            takeOverTitle,
            isPresented: Binding(get: { store.takeOverRequest != nil }, set: { if !$0 { store.takeOverRequest = nil } }),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Take Over")) {
                if let id = store.takeOverRequest { store.takeOver(id) }
                store.takeOverRequest = nil
            }
        } message: {
            Text("ThreadHaven stops the chat where it runs now, closes that terminal window if nothing else runs in it, and continues the same conversation here. Anything it is doing right now is interrupted.")
        }
        .alert(
            String(localized: "Rename Chat"),
            isPresented: Binding(get: { store.renameRequest != nil }, set: { if !$0 { store.renameRequest = nil } })
        ) {
            TextField(String(localized: "Name"), text: $renameText)
            Button(String(localized: "Rename")) {
                if let id = store.renameRequest { store.rename(id, to: renameText) }
                store.renameRequest = nil
            }
            .keyboardShortcut(.defaultAction)
            Button(String(localized: "Cancel"), role: .cancel) { store.renameRequest = nil }
        } message: {
            Text("The name is only shown in ThreadHaven. Leave it empty to use the title from Claude again.")
        }
        .onChange(of: store.renameRequest) { _, id in
            renameText = id.flatMap { store.customTitles[$0] ?? store.session($0)?.title } ?? ""
        }
        .onChange(of: sessions.isEmpty, initial: true) { _, empty in
            if selection.isEmpty, !empty, let first = SidebarLayout(sessions: sessions).ordered.first?.id {
                store.selection = [first]
            }
        }
        .onChange(of: selectionNeedsAttention) { _, attention in
            if attention, NSApp.isActive { selection.forEach(store.markSeen) }
        }
    }

    private var closeTitle: String {
        let title = store.closeRequest.flatMap { store.session($0)?.title } ?? String(localized: "this chat")
        return String(localized: "Close “\(title)”?")
    }

    private var deleteTitle: String {
        let title = store.deleteRequest.flatMap { store.session($0)?.title } ?? String(localized: "this chat")
        return String(localized: "Delete “\(title)”?")
    }

    private var runningPaneIDs: [String] {
        store.terminals.pending.filter { store.terminals.isRunning($0.id) }.map(\.id)
            + SidebarLayout(sessions: store.sessions, favorites: store.favorites).running.map(\.id)
    }

    private var layoutSymbol: String {
        switch selection.count {
        case ...1: "rectangle"
        case 2: "rectangle.split.2x1"
        case 3: "rectangle.split.3x1"
        default: "rectangle.split.2x2"
        }
    }

    private func showPanes(_ count: Int) {
        let ids = PaneGrid.panes(count: count, keeping: paneOrder.filter(selection.contains), running: runningPaneIDs)
        guard !ids.isEmpty else { return }
        paneOrder = ids
        store.selection = Set(ids)
    }

    private var takeOverTitle: String {
        let session = store.takeOverRequest.flatMap { store.session($0) }
        let title = session?.title ?? String(localized: "this chat")
        let place = session?.terminalName ?? String(localized: "another terminal")
        return String(localized: "Move “\(title)” from \(place) to ThreadHaven?")
    }

    private var selectionNeedsAttention: Bool {
        selection.contains { store.session($0)?.needsAttention ?? false }
    }

    private func shortcutButtons(_ live: [Session]) -> some View {
        ZStack {
            ForEach(Array(live.prefix(9).enumerated()), id: \.element.id) { index, s in
                Button("") {
                    store.selection = [s.id]
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
        Button(String(localized: "Rename…")) { store.requestRename(session.id) }
        Divider()
        if store.canTakeOver(session.id) {
            Button(String(localized: "Take Over in ThreadHaven…")) { store.requestTakeOver(session.id) }
        }
        if session.isLive {
            Button(String(localized: "Go to Terminal")) { store.focus(session.id) }
            Button(String(localized: "Compact Now")) { store.compact(session.id) }
                .disabled(!store.canCompact(session.id))
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
        if store.canDelete(session.id) {
            Divider()
            Button(String(localized: "Delete Chat…"), role: .destructive) { store.requestDelete(session.id) }
        }
        Divider()
        Button(String(localized: "Show in Finder")) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: session.cwd)
        }
        Button(String(localized: "Copy Resume Command")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(session.resumeCommand, forType: .string)
        }
        Button(String(localized: "Copy Session ID")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(session.id, forType: .string)
        }
    }
}
