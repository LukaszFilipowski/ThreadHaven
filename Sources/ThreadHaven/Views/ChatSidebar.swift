import SwiftUI
import ThreadHavenCore

struct ChatSidebar: View {
    @Environment(SessionStore.self) private var store
    @Binding var selection: Set<String>
    let sessions: [Session]
    var pending: [EmbeddedTerminals.Pending] = []
    var limit: Int? = 30
    @State private var extra = 0

    var body: some View {
        let layout = SidebarLayout(sessions: sessions, favorites: store.favorites, limit: limit.map { $0 + extra })
        List(selection: $selection) {
            if !store.hooksInstalled {
                HooksBanner()
            }
            if !layout.inApp.isEmpty || !pending.isEmpty {
                Section {
                    ForEach(pending) { item in
                        PendingRow(item: item, onClose: { store.requestClose(item.id) }).tag(item.id)
                    }
                    ForEach(Array(layout.inApp.enumerated()), id: \.element.id) { index, session in
                        ChatRow(session: session, showProject: true, shortcut: index < 9 ? index + 1 : nil,
                                favorite: store.isFavorite(session.id), onClose: { store.requestClose(session.id) })
                            .tag(session.id)
                    }
                } header: {
                    SidebarHeader(title: String(localized: "Running in ThreadHaven"), detail: nil,
                                  count: layout.inApp.count + pending.count, symbol: "macwindow")
                }
            }
            if !layout.outside.isEmpty {
                Section {
                    ForEach(Array(layout.outside.enumerated()), id: \.element.id) { index, session in
                        let position = layout.inApp.count + index
                        ChatRow(session: session, showProject: true, shortcut: position < 9 ? position + 1 : nil,
                                favorite: store.isFavorite(session.id), onClose: { store.requestClose(session.id) },
                                onTakeOver: store.canTakeOver(session.id) ? { store.requestTakeOver(session.id) } : nil)
                            .tag(session.id)
                    }
                } header: {
                    SidebarHeader(title: String(localized: "Running outside ThreadHaven"), detail: nil,
                                  count: layout.outside.count, symbol: "terminal")
                }
            }
            if !layout.favorites.isEmpty {
                Section {
                    ForEach(layout.favorites) { session in
                        ChatRow(session: session, showProject: true, shortcut: nil, favorite: true).tag(session.id)
                    }
                } header: {
                    SidebarHeader(title: String(localized: "Favorites"), detail: nil, count: layout.favorites.count, symbol: "star.fill")
                }
            }
            if !layout.recent.isEmpty {
                Section {
                    ForEach(layout.recent) { session in
                        ChatRow(session: session, showProject: true, shortcut: nil, favorite: false).tag(session.id)
                    }
                    if layout.hidden > 0 {
                        Button(String(localized: "Show \(min(layout.hidden, 30)) more")) { extra += 30 }
                            .buttonStyle(.link)
                            .selectionDisabled()
                    }
                } header: {
                    SidebarHeader(title: String(localized: "Recent"), detail: nil, count: layout.recent.count + layout.hidden, symbol: "clock")
                }
            }
        }
        .listStyle(.sidebar)
        .contextMenu(forSelectionType: String.self) { ids in
            if ids.count > 1 {
                Button(String(localized: "Open Side by Side")) { store.openSideBySide(order(ids)) }
                    .disabled(ids.count > SessionStore.maxPanes)
            } else if let id = ids.first, let session = store.session(id) {
                SessionActions(session: session)
            }
        } primaryAction: { ids in
            if ids.count > 1 {
                store.openSideBySide(order(ids))
            } else if let id = ids.first {
                open(id)
            }
        }
        .overlay {
            if sessions.isEmpty && pending.isEmpty {
                Text("No chats yet").foregroundStyle(.secondary)
            }
        }
    }

    private func order(_ ids: Set<String>) -> [String] {
        let ordered = SidebarLayout(sessions: sessions, favorites: store.favorites).ordered.map(\.id)
        return ordered.filter(ids.contains)
    }

    private func open(_ id: String) {
        guard let session = store.session(id) else { return }
        if session.isLive { store.focus(id) } else { store.resume(id) }
    }
}

struct PendingRow: View {
    @Environment(SessionStore.self) private var store
    let item: EmbeddedTerminals.Pending
    var onClose: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        let linked = item.linkedSession.flatMap(store.session)
        HStack(spacing: 10) {
            Group {
                if let linked {
                    StatusIcon(status: linked.status == .closed ? .idle : linked.status)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(linked?.title ?? String(localized: "Starting…"))
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 5) {
                    Label(item.project, systemImage: "folder")
                    if linked != nil {
                        Text(String(localized: "second window"))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let onClose, hovering {
                CloseChatButton(action: onClose)
            }
        }
        .padding(.vertical, 4)
        .onHover { hovering = $0 }
    }
}

struct SidebarLayout {
    let inApp: [Session]
    let outside: [Session]
    let favorites: [Session]
    let recent: [Session]
    let hidden: Int

    init(sessions: [Session], favorites favoriteIDs: Set<String> = [], limit: Int? = nil) {
        let running = sessions.filter(\.isLive).sorted { ($0.project, $0.id) < ($1.project, $1.id) }
        inApp = running.filter(\.inApp)
        outside = running.filter { !$0.inApp }
        favorites = sessions
            .filter { !$0.isLive && favoriteIDs.contains($0.id) }
            .sorted { $0.lastActivity > $1.lastActivity }
        let all = sessions
            .filter { !$0.isLive && !favoriteIDs.contains($0.id) }
            .sorted { $0.lastActivity > $1.lastActivity }
        let shown = limit.map { max(0, $0) } ?? all.count
        recent = Array(all.prefix(shown))
        hidden = all.count - recent.count
    }

    var running: [Session] { inApp + outside }

    var ordered: [Session] { running + favorites + recent }
}

struct SidebarHeader: View {
    let title: String
    let detail: String?
    let count: Int
    var symbol = "folder.fill"

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            Text(title)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 4)
            Text("\(count)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .help(detail ?? title)
    }
}

struct ChatRow: View {
    let session: Session
    let showProject: Bool
    let shortcut: Int?
    var favorite = false
    var onClose: (() -> Void)?
    var onTakeOver: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusIcon(status: session.status)
                .frame(width: 16, height: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(session.title)
                        .fontWeight(session.needsAttention ? .semibold : .medium)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if favorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    if session.needsAttention {
                        Circle().fill(.orange).frame(width: 8, height: 8)
                    }
                    if hovering, onClose != nil || onTakeOver != nil {
                        if let onTakeOver {
                            TakeOverButton(action: onTakeOver)
                        }
                        if let onClose {
                            CloseChatButton(action: onClose)
                        }
                    } else if let shortcut {
                        Text("⌘\(shortcut)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 5) {
                    if showProject {
                        Label(session.project, systemImage: "folder")
                            .fontWeight(.medium)
                    }
                    if session.isLive {
                        OriginBadge(session: session)
                    }
                    if session.agent != .claude {
                        Text(session.agent.name)
                    }
                    Text(session.lastActivity, format: .relative(presentation: .named))
                        .help(String(localized: "Last activity: \(session.lastActivity.formatted(date: .abbreviated, time: .shortened))"))
                    if session.meta != nil {
                        Text("· \(Int(session.contextFraction * 100))%")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .onHover { hovering = $0 }
    }
}

struct CloseChatButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(String(localized: "Close this chat and stop everything it runs"))
    }
}

struct TakeOverButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.down.forward.square.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(String(localized: "Take over: stop this chat in the other terminal and continue it here"))
    }
}

struct OriginBadge: View {
    let session: Session

    var body: some View {
        if session.inApp {
            Label(String(localized: "in app"), systemImage: "macwindow")
                .foregroundStyle(Color.accentColor)
                .help(String(localized: "Runs in ThreadHaven's terminal"))
        } else {
            Label(session.terminalName, systemImage: "terminal")
                .foregroundStyle(.orange)
                .help(String(localized: "Runs outside ThreadHaven, in \(session.terminalName)"))
        }
    }
}
