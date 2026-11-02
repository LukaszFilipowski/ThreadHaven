import SwiftUI
import ThreadHavenCore

struct ChatSidebar: View {
    @Environment(SessionStore.self) private var store
    @Binding var selection: String?
    let sessions: [Session]
    var pending: [EmbeddedTerminals.Pending] = []
    @AppStorage(Preferences.expandedSections) private var expandedStorage = ""

    private static let favoritesID = "favorites"

    var body: some View {
        let layout = SidebarLayout(sessions: sessions, favorites: store.favorites)
        List(selection: $selection) {
            if !store.hooksInstalled {
                HooksBanner()
            }
            if !layout.running.isEmpty || !pending.isEmpty {
                Section(String(localized: "Running")) {
                    ForEach(pending) { item in
                        PendingRow(item: item, onClose: { store.requestClose(item.id) }).tag(item.id)
                    }
                    ForEach(Array(layout.running.enumerated()), id: \.element.id) { index, session in
                        ChatRow(session: session, showProject: true, shortcut: index < 9 ? index + 1 : nil,
                                favorite: store.isFavorite(session.id), onClose: { store.requestClose(session.id) })
                            .tag(session.id)
                    }
                }
            }
            if !layout.favorites.isEmpty {
                Section(isExpanded: expansion(for: Self.favoritesID)) {
                    ForEach(layout.favorites) { session in
                        ChatRow(session: session, showProject: true, shortcut: nil, favorite: true).tag(session.id)
                    }
                } header: {
                    SidebarHeader(title: String(localized: "Favorites"), detail: nil, count: layout.favorites.count, symbol: "star.fill")
                }
            }
            ForEach(layout.projects) { project in
                Section(isExpanded: expansion(for: project.id)) {
                    ForEach(project.sessions) { session in
                        ChatRow(session: session, showProject: false, shortcut: nil, favorite: false).tag(session.id)
                    }
                } header: {
                    SidebarHeader(title: project.name, detail: project.displayPath, count: project.sessions.count)
                }
            }
        }
        .listStyle(.sidebar)
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let session = store.session(id) {
                SessionActions(session: session)
            }
        } primaryAction: { ids in
            if let id = ids.first { open(id) }
        }
        .overlay {
            if sessions.isEmpty && pending.isEmpty {
                Text("No chats yet").foregroundStyle(.secondary)
            }
        }
    }

    private var expanded: Set<String> {
        Set(expandedStorage.split(separator: "\n").map(String.init))
    }

    private func expansion(for id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isExpanded in
                var ids = expanded
                if isExpanded { ids.insert(id) } else { ids.remove(id) }
                expandedStorage = ids.sorted().joined(separator: "\n")
            }
        )
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
    struct Project: Identifiable {
        let path: String
        let sessions: [Session]
        var id: String { path }
        var name: String { path.isEmpty ? String(localized: "Unknown") : (path as NSString).lastPathComponent }
        var displayPath: String {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
        }
    }

    let running: [Session]
    let favorites: [Session]
    let projects: [Project]

    init(sessions: [Session], favorites favoriteIDs: Set<String> = []) {
        running = sessions.filter(\.isLive).sorted { ($0.project, $0.id) < ($1.project, $1.id) }
        favorites = sessions
            .filter { !$0.isLive && favoriteIDs.contains($0.id) }
            .sorted { $0.lastActivity > $1.lastActivity }
        let recent = sessions.filter { !$0.isLive && !favoriteIDs.contains($0.id) }
        projects = Dictionary(grouping: recent, by: \.cwd)
            .map { Project(path: $0.key, sessions: $0.value.sorted { $0.lastActivity > $1.lastActivity }) }
            .sorted { ($0.sessions.first?.lastActivity ?? .distantPast) > ($1.sessions.first?.lastActivity ?? .distantPast) }
    }

    var ordered: [Session] { running + favorites + projects.flatMap(\.sessions) }
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
                    if let onClose, hovering {
                        CloseChatButton(action: onClose)
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
                    if session.agent != .claude {
                        Text(session.agent.name)
                    }
                    Text(session.lastActivity, format: .relative(presentation: .named))
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
