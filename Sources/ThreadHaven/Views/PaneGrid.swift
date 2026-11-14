import SwiftUI
import ThreadHavenCore

struct PaneGrid: View {
    let ids: [String]

    static func order(_ current: [String], selection: Set<String>, pending: [String]) -> [String] {
        let kept = current.filter(selection.contains)
        let added = selection.subtracting(kept).sorted { a, b in
            let pa = pending.firstIndex(of: a) ?? Int.max
            let pb = pending.firstIndex(of: b) ?? Int.max
            return pa != pb ? pa < pb : a < b
        }
        return kept + added
    }

    static func columns(for count: Int) -> Int {
        switch count {
        case ...3: max(count, 1)
        case 4: 2
        default: 3
        }
    }

    var body: some View {
        let columns = Self.columns(for: ids.count)
        let rows = stride(from: 0, to: ids.count, by: columns).map { Array(ids[$0..<min($0 + columns, ids.count)]) }
        VStack(spacing: 1) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 1) {
                    ForEach(rows[row], id: \.self) { id in
                        CompactPane(id: id, single: false)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if rows[row].count < columns {
                        ForEach(0..<(columns - rows[row].count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .separatorColor))
    }
}

struct CompactPane: View {
    @Environment(SessionStore.self) private var store
    let id: String
    let single: Bool

    var body: some View {
        let session = store.session(id)
        let pending = store.terminals.pending.first { $0.id == id }
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let session {
                    StatusIcon(status: session.status).frame(width: 16, height: 16)
                } else {
                    Image(systemName: "folder.fill").foregroundStyle(Color.accentColor)
                }
                if single {
                    Text(session?.project ?? pending?.project ?? "")
                        .font(.headline)
                        .lineLimit(1)
                }
                Text(title(session: session, pending: pending))
                    .font(single ? .body : .callout.weight(.medium))
                    .foregroundStyle(single ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                    .help(session.map { "\($0.title) · \($0.project)" } ?? "")
                Spacer(minLength: 4)
                if let session {
                    if session.isLive { OriginBadge(session: session).font(.caption).labelStyle(.iconOnly) }
                    SessionIDButton(id: session.id, compact: !single)
                    if store.canTakeOver(session.id) {
                        TakeOverButton { store.requestTakeOver(session.id) }
                    }
                }
                if !single {
                    Button {
                        store.selection = [id]
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "Show only this chat"))
                }
                if session?.isLive == true || store.terminals.isRunning(id) {
                    CloseChatButton { store.requestClose(id) }
                }
            }
            .padding(.horizontal, single ? 18 : 10)
            .padding(.vertical, single ? 14 : 7)
            .frame(height: single ? 48 : 32)
            .background(.bar)
            Divider()
            TerminalPane(id: id, session: session)
        }
        .contentShape(Rectangle())
        .contextMenu {
            if let session { SessionActions(session: session) }
        }
    }

    private func title(session: Session?, pending: EmbeddedTerminals.Pending?) -> String {
        if let session { return session.title }
        return pending?.linkedSession.flatMap { store.session($0)?.title } ?? String(localized: "New chat")
    }
}

struct SessionIDButton: View {
    let id: String
    var compact = false
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(id, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Label(copied ? String(localized: "Copied") : String(id.prefix(8)),
                  systemImage: copied ? "checkmark" : "number")
                .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary.opacity(0.7), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(String(localized: "Copy session ID \(id)"))
        .accessibilityLabel(String(localized: "Copy session ID"))
    }
}

struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView

    init<S: LabelStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}
