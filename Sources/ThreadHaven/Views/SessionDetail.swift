import SwiftUI

struct SessionDetail: View {
    @Environment(SessionStore.self) private var store
    let session: Session
    @State private var messages: [ChatMessage] = []
    @State private var loading = true

    static let coldCacheWarningTokens = 50_000

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
            Divider()
            Composer(session: session)
        }
        .task(id: session.meta?.modified) {
            await loadMessages()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Text(session.cwd)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer()
                StatusPill(session: session)
            }
            if let msg = session.live?.message, session.status == .needsInput {
                Label(msg, systemImage: "hand.raised.fill")
                    .font(.callout)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                if session.isCacheCold(at: context.date), let meta = session.meta, meta.contextTokens >= Self.coldCacheWarningTokens {
                    ColdCacheBanner(session: session, tokens: meta.contextTokens)
                }
            }
            if case .failed(let message) = store.handoffs[session.id] {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack(spacing: 16) {
                if let meta = session.meta {
                    ContextGauge(tokens: meta.contextTokens, window: meta.contextWindow)
                    if let model = meta.model {
                        Label(model, systemImage: "cpu").font(.caption).foregroundStyle(.secondary)
                    }
                    Label(ByteCountFormatter.string(fromByteCount: Int64(meta.size), countStyle: .file), systemImage: "doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                actions
            }
            if let path = session.meta?.path {
                TokenInsightsView(path: path, modified: session.meta?.modified)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 8) {
            if session.isLive {
                Button {
                    store.focus(session.id)
                } label: {
                    Label(String(localized: "Go to Terminal"), systemImage: "terminal")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    store.compact(session.id)
                } label: {
                    Label(String(localized: "Compact"), systemImage: "arrow.down.right.and.arrow.up.left")
                }
                .disabled(!TerminalBridge.canSend(to: session))
                .help(String(localized: "Sends /compact to this chat"))
                HandoffButton(session: session)
            } else {
                Button {
                    store.resume(session.id)
                } label: {
                    Label(String(localized: "Resume"), systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.cwd.isEmpty)
                HandoffButton(session: session)
            }
            Menu {
                SessionActions(session: session)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty && !loading {
                        Text("No messages to show yet.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                    ForEach(messages) { m in
                        MessageBubble(message: m).id(m.id)
                    }
                }
                .padding(16)
            }
            .onChange(of: messages.last?.id) { _, last in
                if let last { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
    }

    private func loadMessages() async {
        guard let path = session.meta?.path ?? session.live?.transcriptPath else {
            loading = false
            return
        }
        let result = await Task.detached(priority: .userInitiated) {
            TranscriptReader.recentMessages(path: path)
        }.value
        messages = result
        loading = false
    }
}

struct HandoffButton: View {
    @Environment(SessionStore.self) private var store
    let session: Session

    var body: some View {
        let running = store.handoffs[session.id] == .running
        Button {
            store.handOff(session.id)
        } label: {
            if running {
                ProgressView().controlSize(.small)
            } else {
                Label(String(localized: "Hand Off"), systemImage: "arrow.uturn.right.circle")
            }
        }
        .disabled(running || session.cwd.isEmpty)
        .help(String(localized: "Writes a handoff note with a cheap model and continues in a fresh chat"))
    }
}

struct ColdCacheBanner: View {
    @Environment(SessionStore.self) private var store
    let session: Session
    let tokens: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "snowflake")
                .foregroundStyle(.blue)
            Text("The prompt cache of this chat has expired, so the next message re-reads all \(ContextGauge.short(tokens)) tokens at full price. Compact it or hand off to a fresh chat first.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if TerminalBridge.canSend(to: session) {
                Button(String(localized: "Compact")) { store.compact(session.id) }
            }
            HandoffButton(session: session)
        }
        .padding(10)
        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct StatusPill: View {
    let session: Session

    var body: some View {
        HStack(spacing: 6) {
            StatusIcon(status: session.status)
            Text(session.status.label)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.6), in: Capsule())
    }
}

struct ContextGauge: View {
    let tokens: Int
    let window: Int

    var body: some View {
        let fraction = window > 0 ? min(1, Double(tokens) / Double(window)) : 0
        HStack(spacing: 8) {
            ContextBar(fraction: fraction).frame(width: 90, height: 6)
            Text("\(Int(fraction * 100))% · \(Self.short(tokens)) / \(Self.short(window))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .help(String(localized: "Context window usage of the last reply"))
    }

    static func short(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1_000_000) : "\(n / 1000)k"
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        let isUser = message.role == .user
        HStack {
            if isUser { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 4) {
                Text(rendered)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let date = message.date {
                    Text(date, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(10)
            .background(isUser ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 10))
            .frame(maxWidth: 720, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 60) }
        }
    }

    private var rendered: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard var text = try? AttributedString(markdown: message.text, options: options) else {
            return AttributedString(message.text)
        }
        for run in text.runs where run.link != nil && !["http", "https"].contains(run.link?.scheme?.lowercased()) {
            text[run.range].link = nil
        }
        return text
    }
}
