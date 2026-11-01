import SwiftUI
import ThreadHavenCore

struct ChatSidebar: View {
    @Environment(SessionStore.self) private var store
    @Binding var selection: String?
    let sessions: [Session]
    @State private var toggled: Set<String> = []

    var body: some View {
        let layout = SidebarLayout(sessions: sessions)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !store.hooksInstalled {
                        HooksBanner().padding(.bottom, 8)
                    }
                    if !layout.running.isEmpty {
                        Section {
                            ForEach(Array(layout.running.enumerated()), id: \.element.id) { index, session in
                                row(session, showProject: true, shortcut: index < 9 ? index + 1 : nil)
                            }
                        } header: {
                            SidebarHeader(title: String(localized: "Running"), detail: nil, symbol: "bolt.fill")
                        }
                    }
                    ForEach(layout.projects) { project in
                        let expanded = isExpanded(project)
                        Section {
                            if expanded {
                                ForEach(project.sessions) { row($0, showProject: false, shortcut: nil) }
                            }
                        } header: {
                            Button {
                                withAnimation(.snappy) { toggle(project) }
                            } label: {
                                SidebarHeader(title: project.name, detail: project.displayPath, symbol: "folder.fill",
                                              count: project.sessions.count, expanded: expanded)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if sessions.isEmpty {
                        Text("No chats yet")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.downArrow) { move(1, in: layout.ordered, proxy: proxy) }
            .onKeyPress(.upArrow) { move(-1, in: layout.ordered, proxy: proxy) }
            .onKeyPress(.return) {
                if let selection { open(selection) }
                return .handled
            }
        }
    }

    private func row(_ session: Session, showProject: Bool, shortcut: Int?) -> some View {
        ChatRow(session: session, showProject: showProject, shortcut: shortcut, selected: selection == session.id)
            .id(session.id)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { open(session.id) }
            .simultaneousGesture(TapGesture().onEnded { selection = session.id })
            .contextMenu { SessionActions(session: session) }
    }

    private func isExpanded(_ project: SidebarLayout.Project) -> Bool {
        let recent = (project.sessions.first?.lastActivity ?? .distantPast) > Date().addingTimeInterval(-7 * 86_400)
        let containsSelection = project.sessions.contains { $0.id == selection }
        return toggled.contains(project.id) ? !recent : (recent || containsSelection)
    }

    private func toggle(_ project: SidebarLayout.Project) {
        if toggled.contains(project.id) { toggled.remove(project.id) } else { toggled.insert(project.id) }
    }

    private func open(_ id: String) {
        guard let session = store.session(id) else { return }
        if session.isLive { store.focus(id) } else { store.resume(id) }
    }

    private func move(_ step: Int, in ordered: [Session], proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !ordered.isEmpty else { return .ignored }
        let current = ordered.firstIndex { $0.id == selection } ?? (step > 0 ? -1 : ordered.count)
        let next = min(max(current + step, 0), ordered.count - 1)
        selection = ordered[next].id
        proxy.scrollTo(ordered[next].id)
        return .handled
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
    let symbol: String
    var count: Int?
    var expanded: Bool?

    var body: some View {
        HStack(spacing: 6) {
            if let expanded {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 0)
            if let count {
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 8)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(detail ?? title)
    }
}

struct ChatRow: View {
    let session: Session
    let showProject: Bool
    let shortcut: Int?
    let selected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusIcon(status: session.status)
                .frame(width: 16, height: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(session.title)
                        .font(.callout.weight(session.needsAttention ? .semibold : .medium))
                        .lineLimit(2)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                    Spacer(minLength: 4)
                    if session.needsAttention {
                        Circle().fill(.orange).frame(width: 8, height: 8)
                    }
                    if let shortcut {
                        Text("⌘\(shortcut)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
                    }
                }
                HStack(spacing: 5) {
                    if showProject {
                        Label(session.project, systemImage: "folder")
                            .labelStyle(.titleAndIcon)
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
                .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 8))
    }
}
