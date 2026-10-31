import SwiftUI

struct WorkspaceView: View {
    @Environment(SessionStore.self) private var store
    @State private var project: String?
    @State private var items: [InventoryItem] = []
    @State private var scanning = false
    @State private var choseDefault = false
    @State private var tab = Tab.inventory
    @State private var refreshID = UUID()
    @State private var toggleMessage: String?

    enum Tab: Hashable {
        case inventory
        case knowledge
        case team
    }

    var body: some View {
        Group {
            switch tab {
            case .inventory: inventory
            case .knowledge: knowledge
            case .team: team
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker(String(localized: "Project"), selection: $project) {
                    Text("All projects").tag(String?.none)
                    Divider()
                    ForEach(store.recentDirectories, id: \.self) { directory in
                        Text((directory as NSString).lastPathComponent).tag(Optional(directory))
                    }
                }
                .pickerStyle(.menu)
                .help(project ?? String(localized: "User scope only"))
            }
            ToolbarItem(placement: .principal) {
                Picker(String(localized: "View"), selection: $tab) {
                    Text("Inventory").tag(Tab.inventory)
                    Text("Knowledge").tag(Tab.knowledge)
                    Text("Team").tag(Tab.team)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    refreshID = UUID()
                    Task { await scan() }
                } label: {
                    Label(String(localized: "Refresh"), systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r")
                .disabled(scanning)
            }
        }
        .onAppear {
            guard !choseDefault else { return }
            choseDefault = true
            project = store.recentDirectories.first
        }
        .task(id: project) { await scan() }
    }

    @ViewBuilder private var knowledge: some View {
        if let project {
            WorkspaceKnowledgeView(project: project, refreshID: refreshID)
        } else {
            ContentUnavailableView(
                String(localized: "Pick a project"),
                systemImage: "books.vertical",
                description: Text("Knowledge keeps a project's CLAUDE.md, memory and handoff notes together.")
            )
        }
    }

    @ViewBuilder private var team: some View {
        if let project {
            WorkspaceTeamView(project: project, refreshID: refreshID)
        } else {
            ContentUnavailableView(
                String(localized: "Pick a project"),
                systemImage: "person.3",
                description: Text("Team shows the plugin marketplaces and plugins a project shares through git.")
            )
        }
    }

    private var inventory: some View {
        let groups = WorkspaceInventory.grouped(items)
        return VStack(spacing: 0) {
            StartupContextHeader(
                onDisk: WorkspaceInventory.baselineTokens(of: items),
                session: measuredSession,
                hasProject: project != nil
            )
            .padding(16)
            if let toggleMessage {
                Label(toggleMessage, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
            Divider()
            List {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.items) { item in
                            InventoryRow(item: item, onToggle: toggleAction(for: item))
                        }
                    } header: {
                        HStack {
                            Label(group.kind.title, systemImage: group.kind.symbol)
                            Spacer()
                            Text(group.tokens, format: .number)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .overlay {
                if scanning && items.isEmpty {
                    ProgressView()
                } else if items.isEmpty {
                    ContentUnavailableView(
                        String(localized: "Nothing found"),
                        systemImage: "tray",
                        description: Text("No CLAUDE.md, memory, skills, commands, agents, MCP servers or plugins were found here.")
                    )
                }
            }
        }
    }

    private var measuredSession: Session? {
        guard let project else { return nil }
        return store.sessions
            .filter { $0.cwd == project && $0.meta?.baselineContext != nil }
            .max { $0.lastActivity < $1.lastActivity }
    }

    private func toggleAction(for item: InventoryItem) -> ((Bool) -> Void)? {
        guard let project, item.kind == .plugin || (item.kind == .mcpServer && item.scope != .plugin) else { return nil }
        let url = URL(fileURLWithPath: project, isDirectory: true)
        return { enabled in Task { await setEnabled(item, enabled, in: url) } }
    }

    private func setEnabled(_ item: InventoryItem, _ enabled: Bool, in project: URL) async {
        do {
            if item.kind == .plugin {
                try await ProjectSettings.setPlugin(item.name, enabled: enabled, project: project)
            } else {
                let fromMcpJson = item.path.hasSuffix(".mcp.json")
                try await Task.detached {
                    try ProjectSettings.setServer(item.name, fromMcpJson: fromMcpJson, enabled: enabled, project: project)
                }.value
            }
            toggleMessage = String(localized: "Saved for this project. New chats here pick it up; restart running ones.")
            await scan()
        } catch {
            toggleMessage = error.localizedDescription
        }
    }

    private func scan() async {
        scanning = true
        let url = project.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let result = await Task.detached(priority: .userInitiated) { WorkspaceInventory.scan(project: url) }.value
        guard !Task.isCancelled else { return }
        items = result
        scanning = false
    }
}

struct StartupContextHeader: View {
    let onDisk: Int
    let session: Session?
    let hasProject: Bool

    var body: some View {
        let measured = session?.meta?.baselineContext ?? 0
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 32) {
                figure(String(localized: "On disk (estimated)"), onDisk)
                if measured > 0 {
                    figure(String(localized: "Measured at start"), measured)
                }
                Spacer()
            }
            if let session, measured > 0 {
                StartupBar(fraction: Double(min(onDisk, measured)) / Double(measured))
                    .frame(height: 8)
                Text("The other \(max(0, measured - onDisk).formatted()) tokens are the system prompt, built-in tools and the tools of connected MCP servers.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("From the first reply of the latest chat in this project, “\(session.title)”, active \(session.lastActivity.formatted(.relative(presentation: .named))).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text(hasProject
                     ? String(localized: "No chat in this project has replied yet, so there is no start-up context to compare with.")
                     : String(localized: "Pick a project to compare these files with the context its latest chat started with."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func figure(_ title: String, _ tokens: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(tokens, format: .number)
                .font(.title2.weight(.semibold).monospacedDigit())
        }
    }
}

struct StartupBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(Color.accentColor)
                    .frame(width: max(4, proxy.size.width * fraction))
            }
        }
    }
}

struct InventoryRow: View {
    let item: InventoryItem
    var onToggle: ((Bool) -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(item.enabled == false ? .secondary : .primary)
                Text(item.scope.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Group {
                if let onToggle {
                    Toggle(String(localized: "On for this project"), isOn: Binding(get: { item.enabled != false }, set: onToggle))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                        .help(String(localized: "On for this project"))
                } else {
                    state
                }
            }
            .font(.caption)
            .frame(width: 130, alignment: .leading)
            Group {
                if let tokens = item.estimatedTokens {
                    Text(tokens, format: .number)
                } else {
                    Text("unknown").foregroundStyle(.tertiary)
                }
            }
            .monospacedDigit()
            .frame(width: 70, alignment: .trailing)
            Button(action: reveal) {
                Image(systemName: "arrow.right.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(String(localized: "Show in Finder"))
        }
        .help(item.path)
        .contextMenu {
            Button(String(localized: "Show in Finder"), action: reveal)
        }
    }

    @ViewBuilder private var state: some View {
        switch item.enabled {
        case false?:
            Label(String(localized: "Off"), systemImage: "minus.circle")
                .foregroundStyle(.secondary)
        case nil where item.kind == .mcpServer:
            Label(String(localized: "Needs approval"), systemImage: "questionmark.circle")
                .foregroundStyle(.orange)
        default:
            Label(String(localized: "On"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    private func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
    }
}

extension InventoryItem.Kind {
    var title: String {
        switch self {
        case .claudeMd: "CLAUDE.md"
        case .memory: String(localized: "Memory")
        case .skill: String(localized: "Skills")
        case .command: String(localized: "Commands")
        case .agent: String(localized: "Agents")
        case .mcpServer: String(localized: "MCP servers")
        case .plugin: String(localized: "Plugins")
        }
    }

    var symbol: String {
        switch self {
        case .claudeMd: "doc.text"
        case .memory: "brain.head.profile"
        case .skill: "wand.and.stars"
        case .command: "command"
        case .agent: "person.2"
        case .mcpServer: "server.rack"
        case .plugin: "puzzlepiece.extension"
        }
    }
}

extension InventoryItem.Scope {
    var title: String {
        switch self {
        case .user: String(localized: "User")
        case .project: String(localized: "Project")
        case .plugin: String(localized: "Plugin")
        }
    }
}
