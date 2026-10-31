import Adwaita
import Foundation
import ThreadHavenCore

struct SessionsView: View {
    @State private var sessions: [SessionRow] = []
    @State private var selection = ""
    @State private var detail = SessionDetail()
    @State private var loading = false
    @State private var notice = ""

    var view: Body {
        OverlaySplitView {
            ScrollView {
                List(sessions, selection: selectionBinding) { session in
                    VStack {
                        Text(session.title)
                            .ellipsize()
                            .halign(.start)
                        Text(session.subtitle)
                            .ellipsize()
                            .caption()
                            .dimLabel()
                            .halign(.start)
                    }
                    .padding(8)
                }
                .sidebarStyle()
            }
            .hscrollbarPolicy(.never)
            .vexpand()
            .topToolbar {
                HeaderBar.start {
                    Button(icon: .default(icon: .viewRefresh)) {
                        refresh()
                    }
                    .tooltip("Refresh")
                    .insensitive(loading)
                }
                .headerBarTitle {
                    WindowTitle(subtitle: "\(sessions.count) recent sessions", title: "ThreadHaven")
                }
            }
            .onAppear {
                refresh()
            }
        } content: {
            VStack {
                if selected == nil {
                    StatusPage(
                        "No Session Selected",
                        icon: .default(icon: .utilitiesTerminal),
                        description: "Pick a Claude Code or Codex session from the last \(SessionLoader.days) days."
                    )
                    .vexpand()
                } else {
                    ScrollView {
                        VStack {
                            if !notice.isEmpty {
                                Text(notice)
                                    .wrap(true)
                                    .error()
                                    .halign(.start)
                                    .padding(6)
                            }
                            statsSection
                            Text("Recent messages")
                                .heading()
                                .halign(.start)
                                .padding(6)
                            ForEach(detail.messages) { message in
                                VStack {
                                    Text(message.role == .user ? "You" : selected?.meta.agent.name ?? "")
                                        .caption()
                                        .dimLabel()
                                        .halign(.start)
                                    Text(message.text)
                                        .wrap(true)
                                        .selectable(true)
                                        .xalign(0)
                                        .halign(.fill)
                                        .padding(4, [.top])
                                }
                                .padding(12)
                                .card()
                                .padding(6)
                            }
                        }
                        .padding(18)
                    }
                    .hscrollbarPolicy(.never)
                    .vexpand()
                }
            }
            .topToolbar {
                HeaderBar.end {
                    Button("Resume") {
                        resume()
                    }
                    .suggested()
                    .insensitive(selected == nil)
                }
                .headerBarTitle {
                    WindowTitle(subtitle: selected?.subtitle ?? "", title: selected?.title ?? "")
                }
            }
        }
    }

    @ViewBuilder private var statsSection: Body {
        if let stats = detail.stats {
            Text("Token usage")
                .heading()
                .halign(.start)
                .padding(6)
            statRow(Array(SessionLoader.statItems(stats).prefix(4)))
            statRow(Array(SessionLoader.statItems(stats).suffix(4)))
        }
    }

    private func statRow(_ items: [StatItem]) -> AnyView {
        ForEach(items) { item in
            VStack {
                Text(item.value)
                    .title3()
                    .halign(.start)
                Text(item.label)
                    .caption()
                    .dimLabel()
                    .halign(.start)
            }
            .padding(12)
            .card()
            .hexpand()
            .padding(6)
        }
        .orientation(.horizontal)
        .homogeneous(true)
    }

    private var selected: SessionRow? {
        sessions.first { $0.id == selection }
    }

    private var selectionBinding: Binding<String> {
        Binding {
            selection
        } set: { id in
            selection = id
            loadDetail()
        }
    }

    private func refresh() {
        loading = true
        inBackground {
            SessionLoader.recentSessions()
        } then: { rows in
            sessions = rows
            loading = false
            if selected == nil { selection = rows.first?.id ?? "" }
            loadDetail()
        }
    }

    private func loadDetail() {
        notice = ""
        guard let meta = selected?.meta else {
            detail = SessionDetail()
            return
        }
        inBackground {
            SessionLoader.detail(for: meta)
        } then: { loaded in
            if loaded.sessionId == selection { detail = loaded }
        }
    }

    private func resume() {
        guard let meta = selected?.meta else { return }
        notice = TerminalLauncher.resume(meta)
            ? ""
            : "No terminal found. Install xdg-terminal-exec or run \(meta.agent.command) \(meta.agent.resumeArguments(meta.sessionId).joined(separator: " ")) yourself."
    }

    private func inBackground<Value: Sendable>(
        _ work: @escaping @Sendable () -> Value,
        then done: @escaping (Value) -> Void
    ) {
        let mailbox = Mailbox<Value>()
        Thread.detachNewThread {
            mailbox.put(work())
        }
        Idle(delay: .milliseconds(50)) {
            guard let value = mailbox.take() else { return true }
            done(value)
            return false
        }
    }
}
