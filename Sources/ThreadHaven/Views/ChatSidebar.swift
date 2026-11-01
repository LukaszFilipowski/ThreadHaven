import SwiftUI
import ThreadHavenCore

struct ChatSidebar: View {
    @Environment(SessionStore.self) private var store
    @Binding var selection: String?
    let sessions: [Session]
    var pending: [EmbeddedTerminals.Pending] = []
    @State private var toggled: Set<String> = []

    var body: some View {
        let layout = SidebarLayout(sessions: sessions)
        List(selection: $selection) {
            if !store.hooksInstalled {
                HooksBanner()
            }
            if !layout.running.isEmpty || !pending.isEmpty {
                Section(String(localized: "Running")) {
                    ForEach(pending) { item in
                        PendingRow(item: item).tag(item.id)
                    }
                    ForEach(Array(layout.running.enumerated()), id: \.element.id) { index, session in
                        ChatRow(session: session, showProject: true, shortcut: index < 9 ? index + 1 : nil)
                            .tag(session.id)
                    }
                }
            }
            ForEach(layout.projects) { project in
                Section(isExpanded: expansion(for: project)) {
                    ForEach(project.sessions) { session in
                        ChatRow(session: session, showProject: false, shortcut: nil).tag(session.id)
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

    private func expansion(for project: SidebarLayout.Project) -> Binding<Bool> {
        let recent = (project.sessions.first?.lastActivity ?? .distantPast) > Date().addingTimeInterval(-7 * 86_400)
        return Binding(
            get: { toggled.contains(project.id) ? !recent : recent || project.sessions.contains { $0.id == selection } },
            set: { expanded in
                if expanded == recent { toggled.remove(project.id) } else { toggled.insert(project.id) }
            }
        )
    }

    private func open(_ id: String) {
        guard let session = store.session(id) else { return }
        if session.isLive { store.focus(id) } else { store.resume(id) }
    }
}

struct PendingRow: View {
    let item: EmbeddedTerminals.Pending

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "New chat"))
                    .font(.callout.weight(.medium))
                Label(item.project, systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
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
    let projects: [Project]

    init(sessions: [Session]) {
        running = sessions.filter(\.isLive).sorted { ($0.project, $0.id) < ($1.project, $1.id) }
        let recent = sessions.filter { !$0.isLive }
        projects = Dictionary(grouping: recent, by: \.cwd)
            .map { Project(path: $0.key, sessions: $0.value.sorted { $0.lastActivity > $1.lastActivity }) }
            .sorted { ($0.sessions.first?.lastActivity ?? .distantPast) > ($1.sessions.first?.lastActivity ?? .distantPast) }
    }

    var ordered: [Session] { running + projects.flatMap(\.sessions) }
}

struct SidebarHeader: View {
    let title: String
    let detail: String?
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
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
                    if session.needsAttention {
                        Circle().fill(.orange).frame(width: 8, height: 8)
                    }
                    if let shortcut {
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
    }
}
