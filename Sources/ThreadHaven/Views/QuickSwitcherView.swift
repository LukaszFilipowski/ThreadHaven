import SwiftUI

struct QuickSwitcherView: View {
    @Environment(SessionStore.self) private var store
    let onPick: (String) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    private var results: [Session] {
        let words = query.lowercased().split(separator: " ")
        return store.sessions
            .filter { session in
                let haystack = "\(session.title) \(session.project) \(session.cwd)".lowercased()
                return words.allSatisfy { haystack.contains($0) }
            }
            .prefix(30)
            .map { $0 }
    }

    var body: some View {
        let results = results
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(String(localized: "Jump to a chat"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit { pick(results) }
            }
            .padding(14)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, session in
                            SessionRow(session: session, shortcut: nil)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 2)
                                .background(index == highlighted ? Color.accentColor.opacity(0.18) : .clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                                .onTapGesture { onPick(session.id) }
                                .id(index)
                        }
                        if results.isEmpty {
                            Text("No matching chats")
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 24)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: highlighted) { _, index in proxy.scrollTo(index) }
            }
        }
        .frame(width: 560, height: 400)
        .background(.regularMaterial)
        .onAppear { focused = true }
        .onChange(of: query) { highlighted = 0 }
        .onKeyPress(.downArrow) { move(1, in: results) }
        .onKeyPress(.upArrow) { move(-1, in: results) }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
    }

    private func move(_ step: Int, in results: [Session]) -> KeyPress.Result {
        guard !results.isEmpty else { return .handled }
        highlighted = (highlighted + step + results.count) % results.count
        return .handled
    }

    private func pick(_ results: [Session]) {
        guard results.indices.contains(highlighted) else { return }
        onPick(results[highlighted].id)
    }
}
