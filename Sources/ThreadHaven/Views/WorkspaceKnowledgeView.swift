import SwiftUI

struct WorkspaceKnowledgeView: View {
    @Environment(SessionStore.self) private var store
    let project: String
    let refreshID: UUID
    @State private var items: [KnowledgeItem] = []
    @State private var loading = false
    @State private var selection: KnowledgeItem.ID?
    @State private var preview = AttributedString()
    @State private var confirmingDelete = false
    @State private var failure: String?

    var body: some View {
        HSplitView {
            list
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 380, maxHeight: .infinity)
            detail
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: "\(project)|\(refreshID)") { await load() }
        .task(id: selection) { await loadPreview() }
        .alert(
            String(localized: "Could not delete the note"),
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button(String(localized: "OK")) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    private var selectedItem: KnowledgeItem? {
        items.first { $0.id == selection }
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(KnowledgeItem.Kind.allCases, id: \.self) { kind in
                let members = items.filter { $0.kind == kind }
                if !members.isEmpty {
                    Section {
                        ForEach(members) { KnowledgeRow(item: $0) }
                    } header: {
                        Label(kind.title, systemImage: kind.symbol)
                    }
                }
            }
        }
        .overlay {
            if loading && items.isEmpty {
                ProgressView()
            } else if items.isEmpty {
                ContentUnavailableView(
                    String(localized: "No knowledge yet"),
                    systemImage: "books.vertical",
                    description: Text("This project has no CLAUDE.md, memory or handoff notes.")
                )
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let item = selectedItem {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.headline)
                    Text((item.path as NSString).abbreviatingWithTildeInPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                Divider()
                ScrollView {
                    Text(preview)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                Divider()
                actions(for: item)
                    .padding(12)
            }
        } else {
            ContentUnavailableView(
                String(localized: "No file selected"),
                systemImage: "doc.text.magnifyingglass",
                description: Text("Select a file to preview it.")
            )
        }
    }

    private func actions(for item: KnowledgeItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(String(localized: "Open in Editor")) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: item.path))
                }
                Button(String(localized: "Show in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
                }
                Spacer()
            }
            if item.kind == .handoff {
                HStack {
                    Button(String(localized: "Start Fresh Chat From Note")) {
                        store.newChat(in: project, continueLast: false, prompt: SessionStore.handoffPrompt(notePath: item.path))
                    }
                    .help(String(localized: "Starts a new chat in this project that reads the note and waits for your confirmation"))
                    Spacer()
                    Button(String(localized: "Delete Note…"), role: .destructive) {
                        confirmingDelete = true
                    }
                }
                .confirmationDialog(
                    String(localized: "Delete this handoff note?"),
                    isPresented: $confirmingDelete,
                    titleVisibility: .visible
                ) {
                    Button(String(localized: "Delete Note"), role: .destructive) {
                        Task { await delete(item) }
                    }
                } message: {
                    Text("“\(item.name)” will be deleted. This cannot be undone.")
                }
            }
        }
    }

    private func load() async {
        loading = true
        let url = URL(fileURLWithPath: project, isDirectory: true)
        let result = await Task.detached(priority: .userInitiated) { KnowledgeBase.scan(project: url) }.value
        guard !Task.isCancelled else { return }
        items = result
        loading = false
        if let selection, !result.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }

    private func loadPreview() async {
        guard let path = selectedItem?.path else {
            preview = AttributedString()
            return
        }
        let text = await Task.detached(priority: .userInitiated) {
            KnowledgeBase.rendered(KnowledgeBase.preview(path: path))
        }.value
        guard !Task.isCancelled else { return }
        preview = text
    }

    private func delete(_ item: KnowledgeItem) async {
        guard item.kind == .handoff else { return }
        let (path, project) = (item.path, project)
        do {
            try await Task.detached(priority: .userInitiated) {
                try KnowledgeBase.deleteNote(path: path, project: project)
            }.value
            items.removeAll { $0.id == item.id }
            if selection == item.id { selection = nil }
        } catch {
            failure = error.localizedDescription
        }
    }
}

struct KnowledgeRow: View {
    let item: KnowledgeItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .help(item.path)
    }

    private var subtitle: String {
        if item.kind == .handoff, let date = item.date {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return ((item.path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath
    }
}

extension KnowledgeItem.Kind {
    var title: String {
        switch self {
        case .claudeMd: "CLAUDE.md"
        case .memory: String(localized: "Memory")
        case .handoff: String(localized: "Handoff notes")
        }
    }

    var symbol: String {
        switch self {
        case .claudeMd: "doc.text"
        case .memory: "brain.head.profile"
        case .handoff: "arrow.uturn.right.circle"
        }
    }
}
